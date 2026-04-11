# frozen_string_literal: true

module Mpp
  class CreatesDepositAddress
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:, challenge_id:)
      @amount_cents = amount_cents
      @currency = currency
      @challenge_id = challenge_id
    end

    STRIPE_API_VERSION = "2026-03-04.preview"

    def call
      payment_intent = create_payment_intent

      deposit_address = extract_deposit_address(payment_intent)

      unless deposit_address
        return Result.failure("Missing Tempo deposit address in Stripe response")
      end

      payment_intent_id = payment_intent["id"]

      # Cache by deposit_address — that is the value the client echoes back
      # in the payment credential, so it must be the lookup key.
      Rails.cache.write(
        "mpp:deposit_address:#{deposit_address}",
        payment_intent_id,
        expires_in: AppConfig::Mpp::CHALLENGE_TTL_SECONDS
      )

      # Persist a pending MppPayment row now so stripe_payment_intent_id is
      # linked to challenge_id up-front. VerifiesCredential will later look
      # this row up by challenge_id and mark it completed.
      MppPayment.create!(
        amount_cents: amount_cents,
        currency: currency,
        challenge_id: challenge_id,
        deposit_address: deposit_address,
        stripe_payment_intent_id: payment_intent_id,
        status: :pending
      )

      Result.success(
        deposit_address: deposit_address,
        payment_intent_id: payment_intent_id
      )
    rescue Stripe::StripeError => e
      Result.failure("Stripe error: #{e.message}")
    end

    private

    attr_reader :amount_cents, :currency, :challenge_id

    def create_payment_intent
      client = Stripe::StripeClient.new(Stripe.api_key)
      response = client.raw_request(
        :post,
        "/v1/payment_intents",
        params: {
          amount: amount_cents,
          currency: currency,
          "payment_method_types[]": "crypto"
        },
        opts: { api_version: STRIPE_API_VERSION }
      )
      parsed = JSON.parse(response.http_body)

      if parsed["error"]
        raise Stripe::CardError.new(
          parsed.dig("error", "message"),
          nil,
          http_status: response.http_status
        )
      end

      parsed
    end

    def extract_deposit_address(payment_intent)
      payment_intent.dig(
        "next_action",
        "crypto_display_details",
        "deposit_addresses",
        "tempo",
        "address"
      )
    end
  end
end
