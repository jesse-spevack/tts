module Api
  module V1
    class BaseController < ActionController::API
      include StructuredLogging

      before_action :authenticate_token!

      private

      attr_reader :current_user

      def authenticate_token!
        result = AuthenticatesApiRequest.call(bearer: extract_bearer_token)

        if result.success?
          @current_user = result.data[:user]
        else
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def extract_bearer_token
        extract_auth_scheme("Bearer")
      end

      def extract_payment_credential
        extract_auth_scheme("Payment")
      end

      # Parse a single auth scheme value from the Authorization header.
      # Supports RFC 9110 comma-separated schemes, e.g.
      #   Authorization: Bearer <token>, Payment <credential>
      def extract_auth_scheme(scheme)
        header = request.headers["Authorization"]
        return nil if header.blank?

        prefix = "#{scheme} "
        header.split(",").each do |part|
          part = part.strip
          return part.split(" ", 2).last if part.start_with?(prefix)
        end

        nil
      end
    end
  end
end
