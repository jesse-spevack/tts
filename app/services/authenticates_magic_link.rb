# frozen_string_literal: true

class AuthenticatesMagicLink
  include StructuredLogging

  def self.call(token:)
    new(token: token).call
  end

  def initialize(token:)
    @token = token
  end

  def call
    return Result.failure("Invalid or expired token") if @token.blank?

    # Find all users with valid tokens to prevent timing attacks
    users = User.with_valid_auth_token

    user = users.find do |u|
      VerifiesHashedToken.call(hashed_token: u.auth_token, raw_token: @token)
    end

    if user
      InvalidatesAuthToken.call(user: user)

      log_info "user_authenticated", user_id: user.id, email: LoggingHelper.mask_email(user.email_address)

      Result.success(user)
    else
      Result.failure("Invalid or expired token")
    end
  end
end
