# frozen_string_literal: true

module Mpp
  class GeneratesChallenge
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:, recipient:)
      @amount_cents = amount_cents
      @currency = currency
      @recipient = recipient
    end

    def call
      realm = AppConfig::Domain::HOST
      method = "tempo"
      intent = "charge"
      # MPP Tempo challenges use token base units and contract address, not fiat
      token_decimals = AppConfig::Mpp::TEMPO_TOKEN_DECIMALS
      amount_base_units = (amount_cents * (10**token_decimals)) / 100
      token_address = AppConfig::Mpp::TEMPO_CURRENCY_TOKEN
      request_json = JSON.generate({
        amount: amount_base_units.to_s,
        currency: token_address,
        recipient: recipient
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
        header_value: header_value
      )
    end

    private

    attr_reader :amount_cents, :currency, :recipient
  end
end
