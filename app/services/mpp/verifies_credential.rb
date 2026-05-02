# frozen_string_literal: true

module Mpp
  # Routes a Payment credential to its method-specific verifier and
  # owns the shared gates: decode, HMAC, expiry, and MppPayment lookup.
  class VerifiesCredential
    def self.call(**kwargs)
      new(**kwargs).call
    end

    # Tempo-only kwargs accepted for backward compat with callers that
    # injected them before the dispatcher split; forwarded to the tempo
    # verifier and ignored on the stripe path.
    def initialize(credential:, token_address: nil, rpc_url: nil)
      @credential = credential
      @token_address = token_address
      @rpc_url = rpc_url
    end

    def call
      parsed = decode_credential
      return parsed if parsed.is_a?(Result) && parsed.failure?

      challenge = parsed["challenge"]
      payload = parsed["payload"]

      hmac_result = Mpp::VerifiesHmac.call(challenge: challenge)
      return hmac_result unless hmac_result.success?

      # Untrusted input — guard against a malformed timestamp 500.
      begin
        expires = Time.iso8601(challenge["expires"])
      rescue ArgumentError, TypeError
        return Result.failure("Invalid expires timestamp")
      end
      return Result.failure("Challenge has expired") if expires < Time.current

      mpp_payment = MppPayment.find_by(challenge_id: challenge["id"])
      return Result.failure("Unknown challenge") unless mpp_payment

      case challenge["method"]
      when "tempo"
        Mpp::VerifiesTempoCredential.call(
          **tempo_kwargs(challenge: challenge, payload: payload, mpp_payment: mpp_payment)
        )
      when "stripe"
        Mpp::VerifiesSptCredential.call(
          challenge: challenge,
          payload: payload,
          mpp_payment: mpp_payment
        )
      else
        Result.failure("Unsupported credential method: #{challenge["method"]}")
      end
    end

    private

    attr_reader :credential, :token_address, :rpc_url

    def tempo_kwargs(challenge:, payload:, mpp_payment:)
      kwargs = { challenge: challenge, payload: payload, mpp_payment: mpp_payment }
      kwargs[:token_address] = token_address unless token_address.nil?
      kwargs[:rpc_url] = rpc_url unless rpc_url.nil?
      kwargs
    end

    def decode_credential
      return Result.failure("Credential is blank") if credential.nil? || credential.empty?

      # mppx emits base64url (RFC 4648 §5), not standard base64.
      decoded = Base64.urlsafe_decode64(credential)
      parsed = JSON.parse(decoded)

      unless parsed.is_a?(Hash) && parsed["challenge"] && parsed["payload"]
        return Result.failure("Invalid credential structure")
      end

      parsed
    rescue ArgumentError
      Result.failure("Invalid base64 encoding")
    rescue JSON::ParserError
      Result.failure("Invalid JSON in credential")
    end
  end
end
