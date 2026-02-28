module Api
  module V1
    module Auth
      class DeviceTokensController < BaseController
        skip_before_action :authenticate_token!

        def create
          device_code = DeviceCode.find_by(user_code: params[:device_code])

          if device_code.nil? || device_code.expired?
            render json: { error: "expired_token" }, status: :bad_request
            return
          end

          unless device_code.confirmed?
            render json: { error: "authorization_pending" }, status: :precondition_required
            return
          end

          render json: {
            access_token: device_code.token,
            user_email: device_code.user.email_address
          }, status: :ok
        end
      end
    end
  end
end
