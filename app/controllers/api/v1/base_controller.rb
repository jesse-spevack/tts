module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_token!

      private

      attr_reader :current_user, :current_api_token

      def authenticate_token!
        token = extract_bearer_token
        api_token = ApiToken.find_by_token(token)

        if api_token.nil?
          render json: { error: "Unauthorized" }, status: :unauthorized
          return
        end

        api_token.update_column(:last_used_at, Time.current)
        @current_api_token = api_token
        @current_user = api_token.user
      end

      def extract_bearer_token
        header = request.headers["Authorization"]
        return nil unless header&.start_with?("Bearer ")

        header.split(" ", 2).last
      end
    end
  end
end
