module Auth
  class DeviceController < ApplicationController
    allow_unauthenticated_access

    def show
      unless authenticated?
        redirect_to login_path(return_to: auth_device_path(code: params[:code]))
        return
      end

      @confirmed = params[:confirmed] == "true"
      @prefilled_code = params[:code]
    end

    def create
      unless authenticated?
        redirect_to login_path(return_to: auth_device_path)
        return
      end

      code = params[:code].to_s.gsub(/[^A-Za-z]/, "").upcase
      device_code = DeviceCode.find_by(user_code: code)

      if device_code.nil?
        flash[:alert] = "Code not found. Please check and try again."
        redirect_to auth_device_path
        return
      end

      result = ConfirmsDeviceCode.call(device_code: device_code, user: Current.user)

      if result.success?
        redirect_to auth_device_path(confirmed: "true")
      else
        flash[:alert] = result.error
        redirect_to auth_device_path
      end
    end
  end
end
