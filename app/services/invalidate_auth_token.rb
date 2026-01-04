# frozen_string_literal: true

class InvalidateAuthToken
  include StructuredLogging

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.update!(auth_token: nil, auth_token_expires_at: nil)

    log_info "auth_token_invalidated", user_id: @user.id

    @user
  end
end
