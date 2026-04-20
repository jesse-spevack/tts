# frozen_string_literal: true

class AuthenticatesMagicLink
  include StructuredLogging

  def self.call(token:, plan: nil, pack_size: nil)
    new(token: token, plan: plan, pack_size: pack_size).call
  end

  def initialize(token:, plan: nil, pack_size: nil)
    @token = token
    @plan = plan
    @pack_size = pack_size
  end

  def call
    return Result.failure("Invalid or expired token") if @token.blank?

    # Find all users with valid tokens to prevent timing attacks
    users = User.with_valid_auth_token

    user = users.find do |u|
      VerifiesHashedToken.call(hashed_token: u.auth_token, raw_token: @token)
    end

    if user
      if user.deactivated?
        log_info "magic_link_deactivated_user", user_id: user.id
        return Result.failure("Invalid or expired token")
      end

      InvalidatesAuthToken.call(user: user)

      log_info "user_authenticated", user_id: user.id, email: LoggingHelper.mask_email(user.email_address)

      Result.success(user)
    else
      Result.failure("Invalid or expired token")
    end
  end
end
