# frozen_string_literal: true

module Mpp
  class GeneratesChallenge
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # token_address: tests inject an alternate to control which currency
    # the challenge is signed under. Production uses the AppConfig default.
    def initialize(amount_cents:, recipient:, voice_tier:, token_address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN)
      @amount_cents = amount_cents
      @recipient = recipient
      @voice_tier = voice_tier
      @token_address = token_address
    end

    def call
      realm = AppConfig::Domain::HOST
      method = "tempo"
      intent = "charge"
      # MPP challenges carry token base units + contract address, not fiat.
      token_decimals = AppConfig::Mpp::TEMPO_TOKEN_DECIMALS
      amount_base_units = (amount_cents * (10**token_decimals)) / 100
      # voice_tier in the HMAC blob blocks "pay Standard, retry Premium" attacks.
      request_json = JSON.generate({
        amount: amount_base_units.to_s,
        currency: token_address,
        recipient: recipient,
        voice_tier: voice_tier.to_s
      })
      request_b64 = Base64.strict_encode64(request_json)
      expires = (Time.current + AppConfig::Mpp::CHALLENGE_TTL_SECONDS).iso8601

      hmac_data = "#{realm}|#{method}|#{intent}|#{request_json}|#{expires}"
      id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

      header_value = "Payment " \
        "id=\"#{id}\", " \
        "realm=\"#{realm}\", " \
        "method=\"#{method}\", " \
        "intent=\"#{intent}\", " \
        "request=\"#{request_b64}\", " \
        "expires=\"#{expires}\""

      Result.success(
        id: id,
        realm: realm,
        method: method,
        intent: intent,
        request: request_b64,
        expires: expires,
        voice_tier: voice_tier,
        header_value: header_value
      )
    end

    private

    attr_reader :amount_cents, :recipient, :voice_tier, :token_address
  end
end
