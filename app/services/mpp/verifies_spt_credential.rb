# frozen_string_literal: true

module Mpp
  # Redeems a Stripe shared_payment_token (SPT) credential by calling
  # Stripe::PaymentIntent.create in confirm-and-charge mode and translating
  # the response into a verifier Result. Single Stripe round-trip per
  # credential — Stripe collapses validate + charge for SPT.
  #
  # Per agent-team-p6wb spike findings (and mppx 0.6.x reference impl
  # at dist/stripe/server/Charge.js):
  #
  #   Stripe::PaymentIntent.create(
  #     {
  #       amount: <challenge.request.amount>,        # fiat cents
  #       currency: <challenge.request.currency>,    # ISO code, e.g. "usd"
  #       confirm: true,
  #       automatic_payment_methods: { enabled: true, allow_redirects: "never" },
  #       shared_payment_granted_token: spt
  #     },
  #     {
  #       idempotency_key: "mppx_<challenge.id>_<spt>",
  #       stripe_version: AppConfig::Mpp::STRIPE_API_VERSION
  #     }
  #   )
  #
  # `shared_payment_granted_token` is a Stripe Machine Payments private-preview
  # field not yet in stripe-ruby 19.x's typed API. It rides through cleanly
  # via the StripeClient#raw_request path (same pattern PodRead already uses
  # in Mpp::CreatesDepositAddress for crypto deposits).
  #
  # Output:
  #
  #   - status=succeeded AND no idempotent-replayed header → Result.success
  #     with tx_hash (= PaymentIntent id) so the rest of the pipeline
  #     (FinalizesNarration / FinalizesEpisode / GeneratesReceipt) flows
  #     unchanged.
  #
  #   - idempotent-replayed: true → Result.failure with reason: :replay.
  #     Stripe still returns the original PaymentIntent on a replayed
  #     idempotency key; the response header is the only signal.
  #     ProcessesMppRequest treats any verifier failure as a 402 re-challenge
  #     so the client can mint a fresh SPT.
  #
  #   - status=requires_action → Result.failure with reason: :requires_action.
  #     3DS/SCA cannot be resolved in the agent flow — re-challenge.
  #
  #   - Stripe::CardError or other Stripe::StripeError → Result.failure
  #     classified by decline_code: try_again_later / processing_error are
  #     transient (Result.failure with permanent: false so the controller
  #     can render 503 instead of 402); everything else is permanent.
  #
  # NOTE: this verifier does NOT cross-check networkId from the challenge
  # request blob against any merchant-side identifier. Stripe's reference
  # verifier (mppx/dist/stripe/server/Charge.js) does not validate networkId
  # — the SPT itself carries merchant binding via Stripe's API. Adding a
  # check here would reject legitimate retries that re-mint an SPT against
  # the same networkId on a fresh challenge. See agent-team-k71e.1 bd notes.
  class VerifiesSptCredential
    include StructuredLogging

    # Stripe decline codes that indicate a transient issue worth retrying.
    # Per agent-team-p6wb finding 5: try_again_later and processing_error
    # surface as transient so the controller can render 503 (vs. the default
    # 402 re-challenge that follows from a permanent decline).
    TRANSIENT_DECLINE_CODES = %w[try_again_later processing_error].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(challenge:, payload:, mpp_payment:)
      @challenge = challenge
      @payload = payload
      @mpp_payment = mpp_payment
    end

    def call
      spt = payload["spt"]
      return Result.failure("Missing spt in payload") if spt.nil? || spt.to_s.empty?

      request_data = parse_request_blob
      return Result.failure("Invalid challenge request blob") if request_data.nil?

      response = redeem_spt(spt: spt, request_data: request_data)

      pi = JSON.parse(response.http_body)
      replayed = response.http_headers&.[]("idempotent-replayed") == "true"

      if replayed
        log_warn "mpp_spt_replay_detected",
          challenge_id: challenge["id"],
          payment_intent_id: pi["id"]
        return Result.failure("SPT replay detected", code: :replay)
      end

      case pi["status"]
      when "succeeded"
        Result.success(
          tx_hash: pi["id"],
          stripe_payment_intent_id: pi["id"],
          challenge_id: challenge["id"],
          voice_tier: voice_tier_from(request_data),
          amount: request_data["amount"]
        )
      when "requires_action"
        log_warn "mpp_spt_requires_action",
          challenge_id: challenge["id"],
          payment_intent_id: pi["id"]
        Result.failure("SPT requires additional action", code: :requires_action)
      else
        log_warn "mpp_spt_unexpected_status",
          challenge_id: challenge["id"],
          payment_intent_id: pi["id"],
          status: pi["status"]
        Result.failure("Unexpected PaymentIntent status: #{pi["status"]}")
      end
    rescue Stripe::CardError => e
      classify_card_error(e)
    rescue Stripe::StripeError => e
      classify_stripe_error(e)
    rescue JSON::ParserError
      Result.failure("Stripe returned invalid JSON")
    end

    private

    attr_reader :challenge, :payload, :mpp_payment

    def redeem_spt(spt:, request_data:)
      client = Stripe::StripeClient.new(Stripe.api_key)
      client.raw_request(
        :post,
        "/v1/payment_intents",
        params: {
          amount: request_data["amount"].to_i,
          currency: request_data["currency"],
          confirm: true,
          "automatic_payment_methods[enabled]": true,
          "automatic_payment_methods[allow_redirects]": "never",
          shared_payment_granted_token: spt
        },
        opts: {
          idempotency_key: "mppx_#{challenge["id"]}_#{spt}",
          stripe_version: AppConfig::Mpp::STRIPE_API_VERSION
        }
      )
    end

    def parse_request_blob
      decoded = Base64.decode64(challenge["request"])
      JSON.parse(decoded)
    rescue JSON::ParserError, ArgumentError
      nil
    end

    def voice_tier_from(request_data)
      request_data["voice_tier"]&.to_sym
    end

    def classify_card_error(error)
      decline_code = decline_code_for(error)
      log_warn "mpp_spt_card_error",
        challenge_id: challenge["id"],
        code: error.code,
        decline_code: decline_code,
        message: error.message
      transient = TRANSIENT_DECLINE_CODES.include?(decline_code)
      Result.failure(
        "Stripe card error: #{error.message}",
        code: transient ? :transient : :card_declined
      )
    end

    def classify_stripe_error(error)
      decline_code = decline_code_for(error)
      log_error "mpp_spt_stripe_error",
        challenge_id: challenge["id"],
        code: error.code,
        decline_code: decline_code,
        message: error.message
      transient = TRANSIENT_DECLINE_CODES.include?(decline_code)
      Result.failure(
        "Stripe error: #{error.message}",
        code: transient ? :transient : :stripe_error
      )
    end

    # Stripe surfaces decline_code in two places depending on which class
    # constructed the error: ErrorObject#decline_code on the parsed body
    # (when stripe-ruby populated json_body), or directly off the json body
    # hash. Check both so we don't miss it on raw_request responses.
    def decline_code_for(error)
      if error.error.respond_to?(:decline_code) && error.error&.decline_code
        return error.error.decline_code
      end
      json = error.json_body
      json.is_a?(Hash) ? json.dig(:error, :decline_code) || json.dig("error", "decline_code") : nil
    end
  end
end
