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

      # Map a ProcessesMppRequest::Outcome to the correct HTTP response.
      # Single place that knows which outcome symbols render which status,
      # body, and headers. Keep this in sync with the outcomes documented
      # on ProcessesMppRequest.
      def render_mpp_result(result)
        outcome = result.data

        case outcome.outcome
        when :invalid_voice
          render json: { error: outcome.error }, status: :unprocessable_entity
        when :challenge_issued
          render_mpp_challenge(outcome)
        when :challenge_provisioning_failed
          render json: { error: "Payment provisioning failed: #{outcome.error}" },
            status: :service_unavailable
        when :created
          response.headers["Payment-Receipt"] = outcome.receipt_header
          render json: { id: outcome.record.prefix_id }, status: :created
        when :loser_conflict
          render json: { error: "Payment already used" }, status: :conflict
        when :creation_failed
          render json: { error: outcome.error }, status: :unprocessable_entity
        else
          raise "Unknown MPP outcome: #{outcome.outcome}"
        end
      end

      def render_mpp_challenge(outcome)
        challenge = outcome.challenge
        response.headers["WWW-Authenticate"] = challenge[:header_value]

        render json: {
          error: "Payment required",
          challenge: {
            id: challenge[:id],
            amount: outcome.amount_cents,
            currency: AppConfig::Mpp::CURRENCY,
            methods: [ "tempo" ],
            realm: challenge[:realm],
            expires: challenge[:expires],
            deposit_address: outcome.deposit_address
          }
        }, status: :payment_required
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
