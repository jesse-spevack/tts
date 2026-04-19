# frozen_string_literal: true

module Mpp
  # Verifies the HMAC (Hash-based Message Authentication Code) on an
  # MPP challenge. Pure function — no I/O, no DB. Returns Result.success
  # when the challenge id matches what our SECRET_KEY would have signed,
  # Result.failure otherwise.
  #
  # The HMAC binds realm, method, intent, request body, and expires
  # into the challenge id so a client cannot tamper with any of those
  # fields between the 402 response and the payment retry.
  class VerifiesHmac
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(challenge:)
      @challenge = challenge
    end

    def call
      request_json = Base64.decode64(challenge["request"])
      hmac_data = "#{challenge["realm"]}|#{challenge["method"]}|#{challenge["intent"]}|#{request_json}|#{challenge["expires"]}"
      expected_id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

      if ActiveSupport::SecurityUtils.secure_compare(expected_id, challenge["id"])
        Result.success
      else
        Result.failure("Challenge HMAC verification failed")
      end
    end

    private

    attr_reader :challenge
  end
end
