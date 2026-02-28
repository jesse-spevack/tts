module Auth
  class DeviceController < ApplicationController
    allow_unauthenticated_access

    def show
      redirect_to login_path(return_to: auth_device_path) unless authenticated?
    end

    def create
      unless authenticated?
        redirect_to login_path(return_to: auth_device_path)
        return
      end

      code = params[:code].to_s.gsub(/[^A-Za-z]/, "").upcase
      device_code = DeviceCode.find_by(user_code: code)

      if device_code.nil?
        flash.now[:alert] = "Code not found. Please check and try again."
        render :show, status: :unprocessable_entity
        return
      end

      result = ConfirmsDeviceCode.call(device_code: device_code, user: Current.user)

      if result.success?
        @confirmed = true
        render :show
      else
        flash.now[:alert] = result.error
        render :show, status: :unprocessable_entity
      end
    end
  end
end
