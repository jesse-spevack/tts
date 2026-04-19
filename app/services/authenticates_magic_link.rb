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
    user = FindsUserByAuthToken.call(raw_token: @token)

    if user
      InvalidatesAuthToken.call(user: user)
      log_info "user_authenticated", user_id: user.id, email: LoggingHelper.mask_email(user.email_address)
      Result.success(user)
    else
      Result.failure("Invalid or expired token")
    end
  end
end
