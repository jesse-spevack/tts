# frozen_string_literal: true

require "net/http"

module Mpp
  class VerifiesCredential
    include StructuredLogging

    TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    # Allowlist of contract addresses the verifier will filter Transfer
    # events against. Defense-in-depth on the HMAC: a leaked secret could
    # otherwise mint a challenge naming any contract and we'd query it.
    # pathUSD (testnet) + USDC.e (mainnet). Adding a new token is a code change.
    KNOWN_TOKEN_ADDRESSES = %w[
      0x20c0000000000000000000000000000000000000
      0x20c000000000000000000000b9537d11c60e8b50
    ].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # token_address is intentionally NOT a kwarg: the verifier reads the
    # currency the challenge was HMAC-signed under and uses that for the
    # Transfer-event filter. Keeps in-flight challenges valid across a
    # TEMPO_CURRENCY_TOKEN env flip (rollback safety).
    def initialize(
      credential:,
      rpc_url: AppConfig::Mpp::TEMPO_RPC_URL
    )
      @credential = credential
      @rpc_url = rpc_url
    end

    def call
      parsed = decode_credential
      return parsed if parsed.is_a?(Result) && parsed.failure?

      challenge = parsed["challenge"]
      payload = parsed["payload"]

      # Phase 1: HMAC verification
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

      # DB row is the authority for the deposit_address bound to this
      # challenge — never trust the client payload here.
      mpp_payment = MppPayment.find_by(challenge_id: challenge["id"])
      return Result.failure("Unknown challenge") unless mpp_payment
      deposit_address = mpp_payment.deposit_address

      # Cache miss = challenge is stale (entry TTL = CHALLENGE_TTL_SECONDS).
      cache_key = "mpp:deposit_address:#{deposit_address}"
      return Result.failure("Deposit address not found in cache") unless Rails.cache.read(cache_key)

      # Parse the HMAC-signed blob early so malformed contents fail before
      # any RPC traffic.
      request_json = Base64.decode64(challenge["request"])
      request_data = JSON.parse(request_json)
      expected_amount = request_data["amount"]
      # Tier is bound by HMAC, but downstream still compares it against the
      # current request's voice (catches "pay Standard, retry Premium").
      voice_tier = request_data["voice_tier"]&.to_sym

      signed_token_address = request_data["currency"]
      # Type-guard before .downcase / .present? — a generator bug or leaked
      # secret could put a non-string here; don't let it surface as a 500.
      unless signed_token_address.is_a?(String) && signed_token_address.present?
        log_warn("mpp.verifier.invalid_currency",
          currency_class: signed_token_address.class.name,
          challenge_id: challenge["id"])
        return Result.failure("Challenge is missing or invalid currency")
      end
      unless KNOWN_TOKEN_ADDRESSES.include?(signed_token_address.downcase)
        # Alert-worthy: either an unannounced token, or — if HMAC is sound —
        # an attempted forgery.
        log_warn("mpp.verifier.unknown_currency",
          currency: signed_token_address,
          challenge_id: challenge["id"])
        return Result.failure("Unsupported challenge currency")
      end

      # mppx sends two credential types:
      #   "hash"      — client already submitted the tx, sends the hash
      #   "signature" — client sends a signed tx, server submits it
      tx_hash = if payload["hash"].present?
        payload["hash"]
      elsif payload["signature"].present?
        submitted = submit_raw_transaction(payload["signature"])
        return submitted if submitted.is_a?(Result) && submitted.failure?
        submitted
      end
      return Result.failure("Missing tx_hash or signature in payload") if tx_hash.nil? || tx_hash.empty?

      # Replay protection
      return Result.failure("Transaction already used") if MppPayment.exists?(tx_hash: tx_hash)

      # Polling needed for "signature" type — submitted tx may not be mined yet.
      receipt = poll_for_receipt(tx_hash)
      return receipt if receipt.is_a?(Result) && receipt.failure?

      return Result.failure("Transaction not found") if receipt.nil?
      return Result.failure("Transaction reverted") unless receipt["status"] == "0x1"

      transfer_result = verify_transfer_log(receipt, deposit_address, expected_amount, signed_token_address)
      return transfer_result if transfer_result&.failure?

      # Persistence is the caller's responsibility.
      Result.success(
        tx_hash: tx_hash,
        amount: expected_amount,
        recipient: deposit_address,
        challenge_id: challenge["id"],
        voice_tier: voice_tier
      )
    end

    private

    attr_reader :credential, :rpc_url

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

    def fetch_transaction_receipt(tx_hash)
      rpc_call("eth_getTransactionReceipt", [ tx_hash ])
    end

    def submit_raw_transaction(signed_tx)
      rpc_call("eth_sendRawTransaction", [ signed_tx ])
    end

    def poll_for_receipt(tx_hash, max_attempts: 20, delay: 0.5)
      max_attempts.times do |attempt|
        receipt = fetch_transaction_receipt(tx_hash)
        return receipt if receipt.is_a?(Result) && receipt.failure?
        return receipt if receipt # non-nil means receipt found

        sleep(delay) if attempt < max_attempts - 1
      end

      nil # receipt not found after all attempts
    end

    def rpc_call(method, params)
      uri = URI(rpc_url)
      request_body = { jsonrpc: "2.0", method: method, params: params, id: 1 }.to_json

      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = AppConfig::Mpp::TEMPO_RPC_OPEN_TIMEOUT_SECONDS
      http.read_timeout = AppConfig::Mpp::TEMPO_RPC_READ_TIMEOUT_SECONDS

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = request_body

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        return Result.failure("RPC HTTP error: #{response.code}")
      end

      body = JSON.parse(response.body)

      if (error = body["error"])
        message = error.is_a?(Hash) ? error["message"] : error.to_s
        return Result.failure("RPC error: #{message}")
      end

      body["result"]
    rescue Net::OpenTimeout, Net::ReadTimeout
      Result.failure("RPC timeout")
    rescue JSON::ParserError
      Result.failure("RPC returned invalid JSON")
    end

    def verify_transfer_log(receipt, deposit_address, expected_amount, token_address)
      logs = receipt["logs"] || []
      # Challenge amount is already in token base units (e.g. 1_000_000 for $1 at 6 decimals).
      expected_base_units = expected_amount.to_i

      matching_log = logs.find do |log|
        topics = log["topics"] || []
        next false unless topics.length >= 3
        next false unless log["address"]&.downcase == token_address.downcase
        next false unless topics[0] == TRANSFER_TOPIC

        # topics[2] = zero-padded recipient address; normalize to 40-char lower-hex.
        log_recipient = topics[2].delete_prefix("0x").downcase.rjust(40, "0")[-40..]
        clean_deposit = deposit_address.delete_prefix("0x").downcase.rjust(40, "0")[-40..]
        next false unless log_recipient == clean_deposit

        # data = hex uint256 in token base units.
        log_amount = log["data"].delete_prefix("0x").to_i(16)
        log_amount == expected_base_units
      end

      return Result.failure("No matching Transfer event found") unless matching_log

      nil
    end
  end
end
