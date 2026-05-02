# frozen_string_literal: true

require "net/http"

module Mpp
  # On-chain verification of an mppx tempo-method credential. Extracted from
  # Mpp::VerifiesCredential as part of agent-team-k71e.4: the dispatcher in
  # VerifiesCredential routes by challenge.method, and this class owns the
  # tempo branch (the original behavior, byte-for-byte). The stripe branch
  # lives in Mpp::VerifiesSptCredential.
  #
  # Inputs:
  #   challenge:    parsed challenge hash from the credential
  #   payload:      parsed payload hash (carries hash or signature)
  #   mpp_payment:  pre-loaded MppPayment row (challenge_id ↔ deposit_address)
  #
  # Output: same Result shape as the prior monolithic VerifiesCredential —
  # success(tx_hash:, amount:, recipient:, challenge_id:, voice_tier:) on
  # green, descriptive Result.failure on every other branch.
  class VerifiesTempoCredential
    include StructuredLogging

    TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # token_address and rpc_url default to AppConfig so production callers
    # don't have to pass them, but tests (and any future multi-token code
    # path) can inject alternates without mutating module constants.
    def initialize(
      challenge:,
      payload:,
      mpp_payment:,
      token_address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
      rpc_url: AppConfig::Mpp::TEMPO_RPC_URL
    )
      @challenge = challenge
      @payload = payload
      @mpp_payment = mpp_payment
      @token_address = token_address
      @rpc_url = rpc_url
    end

    def call
      deposit_address = mpp_payment.deposit_address

      # Cache check remains as a freshness short-circuit: the cache entry
      # expires with CHALLENGE_TTL_SECONDS, so a miss means the challenge
      # is stale even if the DB row still exists.
      cache_key = "mpp:deposit_address:#{deposit_address}"
      return Result.failure("Deposit address not found in cache") unless Rails.cache.read(cache_key)

      # Phase 2: On-chain verification
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

      # Poll for receipt — needed for "signature" type where the tx was
      # just submitted and may not be mined yet. For "hash" type, the
      # receipt should be available immediately.
      receipt = poll_for_receipt(tx_hash)
      return receipt if receipt.is_a?(Result) && receipt.failure?

      # Verify receipt status
      return Result.failure("Transaction not found") if receipt.nil?
      return Result.failure("Transaction reverted") unless receipt["status"] == "0x1"

      # Phase 3: Transfer event log verification
      request_json = Base64.decode64(challenge["request"])
      request_data = JSON.parse(request_json)
      expected_amount = request_data["amount"]
      # voice_tier is embedded in the HMAC-signed request blob, so any
      # tampering is caught by the HMAC check upstream. Downstream callers
      # still compare this against the tier of the CURRENT request's
      # voice to catch the "pay Standard, retry Premium" case.
      voice_tier = request_data["voice_tier"]&.to_sym

      transfer_result = verify_transfer_log(receipt, deposit_address, expected_amount)
      return transfer_result if transfer_result&.failure?

      # Pure verification — persistence is the caller's responsibility.
      # The caller looks up the pending MppPayment by challenge_id (created
      # by CreatesDepositAddress at challenge time) and marks it completed.
      Result.success(
        tx_hash: tx_hash,
        amount: expected_amount,
        recipient: deposit_address,
        challenge_id: challenge["id"],
        voice_tier: voice_tier
      )
    end

    private

    attr_reader :challenge, :payload, :mpp_payment, :token_address, :rpc_url

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

    def verify_transfer_log(receipt, deposit_address, expected_amount)
      logs = receipt["logs"] || []

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
