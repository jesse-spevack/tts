module Api
  module V1
    module Auth
      class DeviceTokensController < BaseController
        skip_before_action :authenticate_token!

        def create
          device_code = DeviceCode.find_by(device_code: params[:device_code])

          if device_code.nil?
            render json: { error: "expired_token" }, status: :bad_request
            return
          end

          result = ExchangesDeviceToken.call(device_code: device_code)

          if result.success?
            render json: result.data, status: :ok
          else
            render json: { error: result.error }, status: :bad_request
          end
        end
      end
    end
  end
end
