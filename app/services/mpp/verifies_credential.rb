# frozen_string_literal: true

module Mpp
  # Routes a Payment credential to the right method-specific verifier.
  #
  # PodRead supports two MPP credential types, both negotiated via parallel
  # challenges in the WWW-Authenticate header (see Mpp::ProvisionsChallenge):
  #
  #   - method="tempo"  → on-chain mppx via Tempo deposit address
  #     (Mpp::VerifiesTempoCredential)
  #   - method="stripe" → Stripe shared_payment_token redemption
  #     (Mpp::VerifiesSptCredential)
  #
  # Both branches share the same upstream gates — credential decode, HMAC
  # verification, expiry check, and MppPayment lookup — so the dispatcher
  # owns those before delegating. Public #call signature is unchanged from
  # the pre-dispatcher VerifiesCredential, so ProcessesMppRequest does not
  # need to know which method was used.
  #
  # Returns the same Result shape as either delegate verifier:
  #   Result.success(tx_hash:, challenge_id:, voice_tier:, ...) on green;
  #   Result.failure(<error message>) on every other branch. Downstream
  #   ProcessesMppRequest converts any failure into a 402 re-challenge.
  class VerifiesCredential
    def self.call(**kwargs)
      new(**kwargs).call
    end

    # token_address and rpc_url are tempo-only knobs (see
    # Mpp::VerifiesTempoCredential). They're accepted here for backward
    # compatibility with existing callers and tests that injected them
    # before the dispatcher split — forwarded straight through to the
    # tempo verifier and ignored on the stripe path.
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

      # Phase 1: HMAC verification — applies to every method.
      hmac_result = Mpp::VerifiesHmac.call(challenge: challenge)
      return hmac_result unless hmac_result.success?

      # Check expiration. Untrusted client input — never let a malformed
      # timestamp bubble up as a 500.
      begin
        expires = Time.iso8601(challenge["expires"])
      rescue ArgumentError, TypeError
        return Result.failure("Invalid expires timestamp")
      end
      return Result.failure("Challenge has expired") if expires < Time.current

      # Look up the MppPayment row created at 402 challenge time. The
      # challenge_id is HMAC-bound (unforgeable), and Mpp::ProvisionsChallenge
      # persists one pending row per method-keyed challenge_id (k71e.1 design),
      # so the row authoritatively identifies which method's verifier should
      # run — independent of any client-supplied hint.
      mpp_payment = MppPayment.find_by(challenge_id: challenge["id"])
      return Result.failure("Unknown challenge") unless mpp_payment

      # Phase 2: dispatch to the method-specific verifier.
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

      # mppx uses base64url (no padding, - and _ instead of + and /)
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
