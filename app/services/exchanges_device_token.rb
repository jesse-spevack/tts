# frozen_string_literal: true

class ExchangesDeviceToken
  include StructuredLogging

  def self.call(device_code:)
    new(device_code: device_code).call
  end

  def initialize(device_code:)
    @device_code = device_code
  end

  def call
    @device_code.with_lock do
      if @device_code.expired?
        return Result.failure("expired_token")
      end

      unless @device_code.confirmed?
        return Result.failure("authorization_pending")
      end

      if @device_code.token_digest.present?
        return Result.failure("expired_token")
      end

      # agent-team-u5l: reject device_codes whose user has been deactivated
      # between confirmation and exchange. Mirrors the deactivated? guard
      # used in Api::V1::BaseController and McpController so all auth
      # surfaces fail closed for deactivated users.
      if @device_code.user.deactivated?
        return Result.failure("expired_token")
      end

      api_token = GeneratesApiToken.call(user: @device_code.user)
      @device_code.update!(token_digest: HashesToken.call(plain_token: api_token.plain_token))

      log_info "device_token_exchanged", device_code_id: @device_code.id, user_id: @device_code.user.id

      Result.success(access_token: api_token.plain_token, user_email: @device_code.user.email_address)
    end
  end
end
