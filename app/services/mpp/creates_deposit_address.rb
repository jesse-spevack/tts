# frozen_string_literal: true

module Mpp
  class CreatesDepositAddress
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # expected_token_address: contract we assert appears in Stripe's
    #   supported_tokens response — defense against silent drift.
    # require_supported_tokens: when true, missing supported_tokens is a
    #   hard fail (prod flip via MPP_REQUIRE_SUPPORTED_TOKENS=1). Default
    #   tolerant so fixtures and older API responses keep working.
    def initialize(
      amount_cents:,
      currency:,
      expected_token_address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
      require_supported_tokens: AppConfig::Mpp::REQUIRE_SUPPORTED_TOKENS
    )
      @amount_cents = amount_cents
      @currency = currency
      @expected_token_address = expected_token_address
      @require_supported_tokens = require_supported_tokens
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

      # Keyed by deposit_address — the on-chain Transfer log's recipient
      # is the lookup we'll need to resolve back to a PaymentIntent.
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

    attr_reader :amount_cents, :currency, :expected_token_address, :require_supported_tokens

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
      raw = payment_intent.dig(
        "next_action",
        "crypto_display_details",
        "deposit_addresses",
        "tempo",
        "address"
      )
      # Canonicalize: Stripe may return EIP-55 checksummed (mixed-case),
      # but cache keys and Transfer-log comparisons all happen in lowercase.
      raw&.downcase
    end

    # Asserts the contract we're about to embed in the challenge appears
    # in Stripe's supported_tokens. Compares on contract address (source
    # of truth), not the "usdc" token_currency literal.
    def verify_supported_tokens(payment_intent)
      tokens = payment_intent.dig(
        "next_action",
        "crypto_display_details",
        "deposit_addresses",
        "tempo",
        "supported_tokens"
      )

      if tokens.nil?
        return nil unless require_supported_tokens
        log_warn("mpp.deposit.supported_tokens_missing", expected: expected_token_address)
        return Result.failure(
          "Stripe deposit response missing supported_tokens; strict mode is on " \
          "(MPP_REQUIRE_SUPPORTED_TOKENS=1). Set to 0 to tolerate."
        )
      end

      contract_addresses = Array(tokens).filter_map { |t| t["token_contract_address"]&.downcase }
      return nil if contract_addresses.include?(expected_token_address.downcase)

      # Drift = silent provisioning of a contract we won't honor. Alert.
      log_warn("mpp.deposit.stripe_drift",
        expected: expected_token_address,
        got: contract_addresses.join(","))
      Result.failure(
        "Stripe deposit does not support expected token #{expected_token_address}; " \
        "got #{contract_addresses.inspect}"
      )
    end
  end
end
