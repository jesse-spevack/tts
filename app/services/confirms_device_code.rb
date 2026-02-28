# frozen_string_literal: true

class ConfirmsDeviceCode
  include StructuredLogging

  def self.call(device_code:, user:)
    new(device_code: device_code, user: user).call
  end

  def initialize(device_code:, user:)
    @device_code = device_code
    @user = user
  end

  def call
    @device_code.with_lock do
      if @device_code.expired?
        log_warn "device_code_confirm_expired", device_code_id: @device_code.id
        return Result.failure("This code has expired. Please try again from your terminal.")
      end

      if @device_code.confirmed?
        log_warn "device_code_already_confirmed", device_code_id: @device_code.id
        return Result.failure("This code has already been used.")
      end

      @device_code.update!(
        user: @user,
        confirmed_at: Time.current
      )

      log_info "device_code_confirmed", device_code_id: @device_code.id, user_id: @user.id

      Result.success(@device_code)
    end
  end
end
