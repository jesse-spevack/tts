# frozen_string_literal: true

class GeneratesApiToken
  include StructuredLogging

  TOKEN_PREFIX = "pk_live_"

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    # Revoke any existing active tokens for this user
    @user.api_tokens.active.find_each do |token|
      token.update!(revoked_at: Time.current)
    end

    # Generate a secure random token
    raw_token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"

    # Create the token record
    token = ApiToken.create!(
      user: @user,
      token_digest: hash_token(raw_token)
    )

    # Set the plain token so it can be returned to the caller once
    token.plain_token = raw_token

    log_info "api_token_generated", user_id: @user.id

    token
  end

  private

  def hash_token(plain_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, plain_token)
  end
end
