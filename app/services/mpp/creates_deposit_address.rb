# frozen_string_literal: true

module Mpp
  class CreatesDepositAddress
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:)
      @amount_cents = amount_cents
      @currency = currency
    end

    STRIPE_API_VERSION = "2026-03-04.preview"

    def call
      payment_intent = create_payment_intent

      deposit_address = extract_deposit_address(payment_intent)

      unless deposit_address
        return Result.failure("Missing Tempo deposit address in Stripe response")
      end

      payment_intent_id = payment_intent["id"]

      # Cache by deposit_address — that is the value the on-chain transfer
      # log references, so it must be the lookup key for any code paths
      # that need to resolve an address back to a Stripe PaymentIntent.
      Rails.cache.write(
        "mpp:deposit_address:#{deposit_address}",
        payment_intent_id,
        expires_in: AppConfig::Mpp::CHALLENGE_TTL_SECONDS
      )

      Result.success(
        deposit_address: deposit_address,
        payment_intent_id: payment_intent_id
      )
    rescue Stripe::StripeError => e
      Result.failure("Stripe error: #{e.message}")
    end

    private

    attr_reader :amount_cents, :currency

    def create_payment_intent
      client = Stripe::StripeClient.new(Stripe.api_key)
      response = client.raw_request(
        :post,
        "/v1/payment_intents",
        params: {
          amount: amount_cents,
          currency: currency,
          "payment_method_types[]": "crypto",
          "payment_method_data[type]": "crypto",
          "payment_method_options[crypto][mode]": "deposit",
          "payment_method_options[crypto][deposit_options][networks][]": "tempo",
          confirm: true
        },
        opts: { stripe_version: STRIPE_API_VERSION }
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
