# frozen_string_literal: true

module Mpp
  # Redeems a Stripe shared_payment_token by calling PaymentIntent.create
  # with the token as a one-time payment source. Stripe collapses validate
  # and charge into a single round-trip.
  #
  # Returns Result.success(tx_hash: <pi_id>) on a fresh succeeded charge.
  # Failures carry a code: :replay, :requires_action, :transient,
  # :card_declined, or :stripe_error.
  #
  # shared_payment_granted_token is private-preview and not in stripe-ruby
  # 19.x's typed API, so we use raw_request. The SPT carries merchant
  # binding via Stripe's API — no need to cross-check networkId.
  class VerifiesSptCredential
    include StructuredLogging

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

    # raw_request can surface decline_code either on the parsed
    # ErrorObject or only in json_body — check both.
    def decline_code_for(error)
      if error.error.respond_to?(:decline_code) && error.error&.decline_code
        return error.error.decline_code
      end
      json = error.json_body
      json.is_a?(Hash) ? json.dig(:error, :decline_code) || json.dig("error", "decline_code") : nil
    end
  end
end
