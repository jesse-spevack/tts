# frozen_string_literal: true

module Mpp
  class CreatesDepositAddress
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:, recipient:)
      @amount_cents = amount_cents
      @currency = currency
      @recipient = recipient
    end

    STRIPE_API_VERSION = "2026-03-04.preview"

    def call
      payment_intent = create_payment_intent

      deposit_address = extract_deposit_address(payment_intent)

      unless deposit_address
        return Result.failure("Missing Tempo deposit address in Stripe response")
      end

      payment_intent_id = payment_intent["id"]

      Rails.cache.write("mpp:deposit_address:#{payment_intent_id}", deposit_address, expires_in: 5.minutes)

      Result.success(
        deposit_address: deposit_address,
        payment_intent_id: payment_intent_id
      )
    rescue Stripe::StripeError => e
      Result.failure("Stripe error: #{e.message}")
    end

    private

    attr_reader :amount_cents, :currency, :recipient

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
