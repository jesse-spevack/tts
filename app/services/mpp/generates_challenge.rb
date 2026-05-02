# frozen_string_literal: true

module Mpp
  # Builds an HMAC-signed MPP 402 challenge for either method:
  # tempo (on-chain via a Tempo deposit address, amount in token base
  # units) or stripe (SPT redemption, amount in fiat cents). Method is
  # part of the HMAC pre-image, so swapping methods between issuance
  # and retry invalidates the credential.
  class GeneratesChallenge
    include StructuredLogging

    SUPPORTED_METHODS = %i[tempo stripe].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:, voice_tier:, recipient: nil, method: :tempo)
      @amount_cents = amount_cents
      @currency = currency
      @recipient = recipient
      @voice_tier = voice_tier
      @method = method.to_sym
      raise ArgumentError, "Unsupported method: #{method}" unless SUPPORTED_METHODS.include?(@method)
      raise ArgumentError, "recipient is required for method=tempo" if @method == :tempo && @recipient.nil?
    end

    def call
      realm = AppConfig::Domain::HOST
      method_str = @method.to_s
      intent = "charge"
      # voice_tier in the blob blocks "pay Standard, retry Premium" via HMAC.
      request_json = JSON.generate(request_blob)
      request_b64 = Base64.strict_encode64(request_json)
      expires = (Time.current + AppConfig::Mpp::CHALLENGE_TTL_SECONDS).iso8601

      hmac_data = "#{realm}|#{method_str}|#{intent}|#{request_json}|#{expires}"
      id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

      header_value = "Payment " \
        "id=\"#{id}\", " \
        "realm=\"#{realm}\", " \
        "method=\"#{method_str}\", " \
        "intent=\"#{intent}\", " \
        "request=\"#{request_b64}\", " \
        "expires=\"#{expires}\""

      Result.success(
        id: id,
        realm: realm,
        method: method_str,
        intent: intent,
        request: request_b64,
        expires: expires,
        voice_tier: voice_tier,
        header_value: header_value
      )
    end

    private

    attr_reader :amount_cents, :currency, :recipient, :voice_tier

    def request_blob
      case @method
      when :tempo  then tempo_request_blob
      when :stripe then stripe_request_blob
      end
    end

    # Quote in token base units to match the on-chain Transfer event.
    def tempo_request_blob
      token_decimals = AppConfig::Mpp::TEMPO_TOKEN_DECIMALS
      amount_base_units = (amount_cents * (10**token_decimals)) / 100
      token_address = AppConfig::Mpp::TEMPO_CURRENCY_TOKEN
      {
        amount: amount_base_units.to_s,
        currency: token_address,
        recipient: recipient,
        voice_tier: voice_tier.to_s
      }
    end

    # Fiat cents + ISO code — same values passed to PaymentIntent.create
    # at SPT redemption. mppx's decoder requires networkId.
    def stripe_request_blob
      {
        amount: amount_cents.to_s,
        currency: currency,
        networkId: AppConfig::Mpp::STRIPE_NETWORK_ID,
        voice_tier: voice_tier.to_s
      }
    end
  end
end
