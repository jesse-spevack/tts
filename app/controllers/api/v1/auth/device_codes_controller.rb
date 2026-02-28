module Api
  module V1
    module Auth
      class DeviceCodesController < BaseController
        skip_before_action :authenticate_token!

        def create
          device_code = CreatesDeviceCode.call

          render json: {
            device_code: device_code.device_code,
            verification_url: "#{AppConfig::Domain::BASE_URL}/auth/device?code=#{device_code.user_code[0..3]}-#{device_code.user_code[4..7]}",
            user_code: "#{device_code.user_code[0..3]}-#{device_code.user_code[4..7]}",
            expires_in: DeviceCode::EXPIRATION.to_i,
            interval: 5
          }, status: :ok
        end
      end
    end
  end
end
