# frozen_string_literal: true

module Mpp
  class CreatesDepositAddress
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # expected_token_address defaults to AppConfig::Mpp::TEMPO_CURRENCY_TOKEN.
    # Stripe's PaymentIntent response on the Tempo network includes a
    # supported_tokens array — we assert the contract we're about to bind
    # into the challenge actually appears there. Defends against Stripe
    # drift (different default token, network enum changes) silently
    # provisioning the wrong contract (agent-team-5aas).
    def initialize(amount_cents:, currency:, expected_token_address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN)
      @amount_cents = amount_cents
      @currency = currency
      @expected_token_address = expected_token_address
    end

    def call
      payment_intent = create_payment_intent

      deposit_address = extract_deposit_address(payment_intent)

      unless deposit_address
        return Result.failure("Missing Tempo deposit address in Stripe response")
      end

      supported_check = verify_supported_tokens(payment_intent)
      return supported_check if supported_check&.failure?

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

    attr_reader :amount_cents, :currency, :expected_token_address

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
        opts: { stripe_version: AppConfig::Mpp::STRIPE_API_VERSION }
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

    # Defense-in-depth (agent-team-5aas): if Stripe ever drifts to provisioning
    # a deposit for a different contract than the one we're about to embed in
    # the challenge, we fail loud BEFORE the doomed 402 reaches the client.
    # token_currency (e.g. "usdc") is irrelevant — the contract address is
    # the source of truth.
    def verify_supported_tokens(payment_intent)
      tokens = payment_intent.dig(
        "next_action",
        "crypto_display_details",
        "deposit_addresses",
        "tempo",
        "supported_tokens"
      )

      # Tolerate a missing supported_tokens array (e.g. older API versions
      # or test fixtures that don't include it) — only fail when Stripe
      # affirmatively returns tokens that don't include the expected one.
      return nil if tokens.nil?

      contract_addresses = Array(tokens).filter_map { |t| t["token_contract_address"]&.downcase }
      return nil if contract_addresses.include?(expected_token_address.downcase)

      Result.failure(
        "Stripe deposit does not support expected token #{expected_token_address}; " \
        "got #{contract_addresses.inspect}"
      )
    end
  end
end
