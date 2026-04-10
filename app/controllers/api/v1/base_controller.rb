module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_token!

      private

      attr_reader :current_user, :current_api_token

      def authenticate_token!
        token = extract_bearer_token

        # Try API token first (CLI, browser extension)
        if authenticate_via_api_token(token)
          return
        end

        # Fall back to Doorkeeper OAuth token (ChatGPT, future OAuth clients)
        if authenticate_via_doorkeeper(token)
          return
        end

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def authenticate_via_api_token(token)
        api_token = FindsApiToken.call(plain_token: token)
        return false if api_token.nil?

        api_token.update_column(:last_used_at, Time.current)
        @current_api_token = api_token
        @current_user = api_token.user
        true
      end

      def authenticate_via_doorkeeper(token)
        return false if token.blank?

        doorkeeper_token = Doorkeeper::AccessToken.by_token(token)
        return false if doorkeeper_token.nil?
        return false if doorkeeper_token.revoked?
        return false if doorkeeper_token.expired?

        @current_user = User.find_by(id: doorkeeper_token.resource_owner_id)
        @current_user.present?
      end

      def extract_bearer_token
        header = request.headers["Authorization"]
        return nil if header.blank?

        # Support RFC 9110 comma-separated schemes:
        # Authorization: Bearer <token>, Payment <credential>
        header.split(",").each do |part|
          part = part.strip
          if part.start_with?("Bearer ")
            return part.split(" ", 2).last
          end
        end

        nil
      end
    end
  end
end
