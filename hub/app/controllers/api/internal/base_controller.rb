module Api
  module Internal
    class BaseController < ApplicationController
      skip_before_action :require_authentication
      skip_forgery_protection
      before_action :verify_generator_secret

      private

      def verify_generator_secret
        secret = request.headers["X-Generator-Secret"]
        expected = ENV.fetch("HUB_CALLBACK_SECRET", nil)

        unless expected && ActiveSupport::SecurityUtils.secure_compare(secret.to_s, expected)
          Rails.logger.warn "event=unauthorized_callback_attempt ip=#{request.remote_ip}"
          render json: { status: "error", message: "Unauthorized" }, status: :unauthorized
        end
      end
    end
  end
end
