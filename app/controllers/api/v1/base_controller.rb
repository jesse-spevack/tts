module Api
  module V1
    class BaseController < ActionController::API
      include StructuredLogging

      before_action :authenticate_token!

      private

      attr_reader :current_user, :current_api_token

      def authenticate_token!
        # Idempotent: MppPayable#handle_mpp_auth may have already
        # authenticated the bearer token earlier in the chain. Skipping
        # here avoids a duplicate DB write to api_token.last_used_at.
        return if @current_user.present?

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
        Current.api_token_prefix = api_token.token_prefix
        log_info "api_request_authenticated",
          user_id: api_token.user_id,
          source: api_token.source
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
