# frozen_string_literal: true

# Authenticates a Bearer-token API request for the /api/v1 surface.
#
# Tries the API token path first (CLI, browser extension), then falls
# back to Doorkeeper OAuth (ChatGPT, future OAuth clients).
#
# Side effects on success:
#   - API token path: updates ApiToken#last_used_at and sets
#     Current.api_token_prefix; emits structured log "api_request_authenticated".
#   - OAuth path: no Current mutation, no log emission (matches pre-refactor
#     behavior).
#
# Side effects on failure:
#   - Deactivated user: emits "api_token_deactivated_user" or
#     "oauth_token_deactivated_user" depending on which path matched.
#   - Other failures: silent (no log, no Current mutation).
#
# Returns Result:
#   - success — data is { user:, source: "api_token"|"oauth", api_token: }
#   - failure — error "Unauthorized", code :unauthorized
class AuthenticatesApiRequest
  include StructuredLogging

  def self.call(bearer:)
    new(bearer: bearer).call
  end

  def initialize(bearer:)
    @bearer = bearer
  end

  def call
    api_token_result = authenticate_via_api_token
    return api_token_result if api_token_result

    oauth_result = authenticate_via_doorkeeper
    return oauth_result if oauth_result

    Result.failure("Unauthorized", code: :unauthorized)
  end

  private

  # Returns a successful Result if the bearer matches a valid, active API
  # token. Returns nil to signal "fall through to Doorkeeper" — this
  # includes the case where the API token belongs to a deactivated user,
  # matching the pre-refactor behavior exactly.
  def authenticate_via_api_token
    api_token = FindsApiToken.call(plain_token: @bearer)
    return nil if api_token.nil?

    user = api_token.user
    if user.deactivated?
      log_info "api_token_deactivated_user", user_id: user.id
      return nil
    end

    api_token.update_column(:last_used_at, Time.current)
    Current.api_token_prefix = api_token.token_prefix
    log_info "api_request_authenticated",
      user_id: api_token.user_id,
      source: api_token.source

    Result.success(user: user, source: "api_token", api_token: api_token)
  end

  # Returns a successful Result if the bearer matches a valid Doorkeeper
  # token for an active user. Returns nil otherwise (including deactivated
  # user — matches the pre-refactor fall-through behavior).
  def authenticate_via_doorkeeper
    return nil if @bearer.blank?

    doorkeeper_token = Doorkeeper::AccessToken.by_token(@bearer)
    return nil if doorkeeper_token.nil?
    return nil if doorkeeper_token.revoked?
    return nil if doorkeeper_token.expired?

    user = User.find_by(id: doorkeeper_token.resource_owner_id)
    return nil if user.nil?

    if user.deactivated?
      log_info "oauth_token_deactivated_user", user_id: user.id
      return nil
    end

    Result.success(user: user, source: "oauth", api_token: nil)
  end
end
