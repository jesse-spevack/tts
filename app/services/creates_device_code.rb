# frozen_string_literal: true

class CreatesDeviceCode
  include StructuredLogging

  # Characters excluding ambiguous ones (O/0/I/1/L)
  SAFE_CHARS = ("A".."Z").to_a - %w[O I L]

  MAX_RETRIES = 5

  def self.call
    new.call
  end

  def call
    device_code = nil
    retries = 0

    loop do
      device_code = DeviceCode.create!(
        device_code: generate_device_code,
        user_code: generate_user_code,
        expires_at: DeviceCode::EXPIRATION.from_now
      )
      break
    rescue ActiveRecord::RecordNotUnique
      retries += 1
      raise if retries >= MAX_RETRIES
    end

    log_info "device_code_created", device_code_id: device_code.id

    device_code
  end

  private

  def generate_device_code
    Array.new(8) { SAFE_CHARS.sample }.join
  end

  def generate_user_code
    SecureRandom.urlsafe_base64(32)
  end
end
