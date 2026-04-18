# frozen_string_literal: true

class GeneratesApiToken
  include StructuredLogging

  TOKEN_PREFIX = "sk_live_"
  # Number of chars from the random portion to expose in token_prefix for
  # display (settings UI, logs). 4 chars of url-safe-base64 is ~24 bits —
  # enough to visually distinguish tokens without narrowing the keyspace.
  DISPLAY_PREFIX_CHARS = 4

  def self.call(user:, source: "user")
    new(user: user, source: source).call
  end

  def initialize(user:, source: "user")
    @user = user
    @source = source
  end

  def call
    random = SecureRandom.urlsafe_base64(32)
    raw_token = "#{TOKEN_PREFIX}#{random}"
    token_prefix = "#{TOKEN_PREFIX}#{random[0, DISPLAY_PREFIX_CHARS]}"

    token = ApiToken.create!(
      user: @user,
      source: @source,
      token_digest: HashesToken.call(plain_token: raw_token),
      token_prefix: token_prefix
    )
    token.plain_token = raw_token

    log_info "api_token_generated",
      user_id: @user.id,
      source: @source,
      token_prefix: token_prefix

    token
  end
end
