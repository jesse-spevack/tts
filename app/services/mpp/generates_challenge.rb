# frozen_string_literal: true

module Mpp
  # Builds an HMAC-signed MPP 402 challenge. PodRead supports two
  # payment methods, both negotiated via parallel challenges in the
  # WWW-Authenticate header (RFC 9110 challenge-list):
  #
  #   - method: :tempo  — on-chain payment via a Tempo deposit address.
  #     The challenge request blob carries amount/currency/recipient/voice_tier
  #     where amount is in token base units and currency is the token
  #     contract address.
  #
  #   - method: :stripe — Stripe shared_payment_token (SPT) redemption
  #     via @stripe/link-cli or any other Stripe Link wallet client.
  #     The challenge request blob carries amount/currency/networkId/voice_tier
  #     where amount is fiat cents (string) and currency is the fiat ISO
  #     code. networkId is Stripe MPP's namespace discriminator.
  #
  # The HMAC pre-image includes the method, so swapping methods between
  # issuance and retry invalidates the credential. Both methods share the
  # same Mpp::VerifiesHmac without modification.
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
      # voice_tier is embedded in the request blob so tampering with the
      # tier on retry (e.g. paying a Standard price but requesting a
      # Premium voice) fails HMAC verification downstream.
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

    # Tempo MPP challenges quote in token base units against a token
    # contract address — both ends of the on-chain Transfer event log
    # use these units, so converting cents -> base units here keeps
    # VerifiesCredential's verify_transfer_log comparison straightforward.
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

    # Stripe MPP challenges quote in fiat cents against the ISO currency
    # code — these are the same values the merchant will pass to
    # Stripe::PaymentIntent.create at SPT redemption time (k71e.5).
    # networkId is required by mppx's stripe decoder; without it the
    # client throws before even attempting payment. See the bd note on
    # agent-team-k71e.1 for the (still open) insider question on what
    # the real production value should be — the placeholder in
    # AppConfig::Mpp::STRIPE_NETWORK_ID round-trips correctly until then.
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
