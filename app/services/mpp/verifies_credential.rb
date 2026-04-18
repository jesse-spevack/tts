# frozen_string_literal: true

require "net/http"

module Mpp
  class VerifiesCredential
    include StructuredLogging

    TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(credential:)
      @credential = credential
    end

    def call
      parsed = decode_credential
      return parsed if parsed.is_a?(Result) && parsed.failure?

      challenge = parsed["challenge"]
      payload = parsed["payload"]

      # Phase 1: HMAC verification
      hmac_result = verify_hmac(challenge)
      return hmac_result if hmac_result&.failure?

      # Check expiration. Untrusted client input — never let a malformed
      # timestamp bubble up as a 500.
      begin
        expires = Time.iso8601(challenge["expires"])
      rescue ArgumentError, TypeError
        return Result.failure("Invalid expires timestamp")
      end
      return Result.failure("Challenge has expired") if expires < Time.current

      # Look up deposit_address from the MppPayment row created at 402
      # challenge time. The challenge_id is HMAC-bound (unforgeable), so
      # the DB row is the authority for which deposit_address belongs to
      # this challenge — never trust the client payload for this value.
      mpp_payment = MppPayment.find_by(challenge_id: challenge["id"])
      return Result.failure("Unknown challenge") unless mpp_payment
      deposit_address = mpp_payment.deposit_address

      # Cache check remains as a freshness short-circuit: the cache entry
      # expires with CHALLENGE_TTL_SECONDS, so a miss means the challenge
      # is stale even if the DB row still exists.
      cache_key = "mpp:deposit_address:#{deposit_address}"
      return Result.failure("Deposit address not found in cache") unless Rails.cache.read(cache_key)

      # Phase 2: On-chain verification
      tx_hash = payload["hash"]
      return Result.failure("Missing tx_hash in payload") if tx_hash.nil? || tx_hash.empty?

      # Replay protection
      return Result.failure("Transaction already used") if MppPayment.exists?(tx_hash: tx_hash)

      receipt = fetch_transaction_receipt(tx_hash)
      return receipt if receipt.is_a?(Result) && receipt.failure?

      # Verify receipt status
      return Result.failure("Transaction not found") if receipt.nil?
      return Result.failure("Transaction reverted") unless receipt["status"] == "0x1"

      # Phase 3: Transfer event log verification
      request_json = Base64.decode64(challenge["request"])
      request_data = JSON.parse(request_json)
      expected_amount = request_data["amount"]

      transfer_result = verify_transfer_log(receipt, deposit_address, expected_amount)
      return transfer_result if transfer_result&.failure?

      # Pure verification — persistence is the caller's responsibility.
      # The caller looks up the pending MppPayment by challenge_id (created
      # by CreatesDepositAddress at challenge time) and marks it completed.
      Result.success(
        tx_hash: tx_hash,
        amount: expected_amount,
        recipient: deposit_address,
        challenge_id: challenge["id"]
      )
    end

    private

    attr_reader :credential

    def decode_credential
      return Result.failure("Credential is blank") if credential.nil? || credential.empty?

      decoded = Base64.strict_decode64(credential)
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

    def verify_hmac(challenge)
      realm = challenge["realm"]
      method = challenge["method"]
      intent = challenge["intent"]
      request_b64 = challenge["request"]
      expires = challenge["expires"]

      request_json = Base64.decode64(request_b64)

      hmac_data = "#{realm}|#{method}|#{intent}|#{request_json}|#{expires}"
      expected_id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

      unless ActiveSupport::SecurityUtils.secure_compare(expected_id, challenge["id"])
        return Result.failure("Challenge HMAC verification failed")
      end

      nil
    end

    def fetch_transaction_receipt(tx_hash)
      uri = URI(AppConfig::Mpp::TEMPO_RPC_URL)
      request_body = {
        jsonrpc: "2.0",
        method: "eth_getTransactionReceipt",
        params: [ tx_hash ],
        id: 1
      }.to_json

      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = AppConfig::Mpp::TEMPO_RPC_OPEN_TIMEOUT_SECONDS
      http.read_timeout = AppConfig::Mpp::TEMPO_RPC_READ_TIMEOUT_SECONDS

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = request_body

      response = http.request(request)

      # Net::HTTP does not raise on non-2xx; check explicitly before parsing.
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

    def verify_transfer_log(receipt, deposit_address, expected_amount)
      logs = receipt["logs"] || []
      token_address = AppConfig::Mpp::TEMPO_CURRENCY_TOKEN

      # The challenge request amount is already in token base units (e.g.,
      # "1000000" for $1 USDC with 6 decimals). Convert to integer for
      # comparison against the on-chain Transfer event data field.
      expected_base_units = expected_amount.to_i

      matching_log = logs.find do |log|
        topics = log["topics"] || []
        next false unless topics.length >= 3
        next false unless log["address"]&.downcase == token_address.downcase
        next false unless topics[0] == TRANSFER_TOPIC

        # topics[2] contains the recipient address, zero-padded to 32 bytes
        # Normalize both to 40-char lowercase hex for comparison
        log_recipient = topics[2].delete_prefix("0x").downcase.rjust(40, "0")[-40..]
        clean_deposit = deposit_address.delete_prefix("0x").downcase.rjust(40, "0")[-40..]
        next false unless log_recipient == clean_deposit

        # Verify amount: data field is hex uint256 in token base units
        log_amount = log["data"].delete_prefix("0x").to_i(16)
        log_amount == expected_base_units
      end

      return Result.failure("No matching Transfer event found") unless matching_log

      nil
    end
  end
end
