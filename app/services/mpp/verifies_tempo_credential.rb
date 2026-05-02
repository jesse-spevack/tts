# frozen_string_literal: true

require "net/http"

module Mpp
  # On-chain verification of a tempo-method credential: confirms the
  # client paid the right amount to the right deposit address by
  # inspecting the Transfer event on the receipt.
  class VerifiesTempoCredential
    include StructuredLogging

    TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # token_address and rpc_url default to AppConfig; tests can inject
    # alternates without mutating module constants.
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

      # Cache miss means the challenge is stale even if the DB row remains;
      # the cache entry expires with CHALLENGE_TTL_SECONDS.
      cache_key = "mpp:deposit_address:#{deposit_address}"
      return Result.failure("Deposit address not found in cache") unless Rails.cache.read(cache_key)

      # mppx sends either a hash (client-submitted tx) or signature
      # (client signs, server submits).
      tx_hash = if payload["hash"].present?
        payload["hash"]
      elsif payload["signature"].present?
        submitted = submit_raw_transaction(payload["signature"])
        return submitted if submitted.is_a?(Result) && submitted.failure?
        submitted
      end
      return Result.failure("Missing tx_hash or signature in payload") if tx_hash.nil? || tx_hash.empty?

      return Result.failure("Transaction already used") if MppPayment.exists?(tx_hash: tx_hash)

      # Signature path may not be mined yet; hash path is usually immediate.
      receipt = poll_for_receipt(tx_hash)
      return receipt if receipt.is_a?(Result) && receipt.failure?

      return Result.failure("Transaction not found") if receipt.nil?
      return Result.failure("Transaction reverted") unless receipt["status"] == "0x1"

      request_json = Base64.decode64(challenge["request"])
      request_data = JSON.parse(request_json)
      expected_amount = request_data["amount"]
      # voice_tier is HMAC-bound. The caller also compares this against
      # the current request's voice tier to catch retry-with-different-tier.
      voice_tier = request_data["voice_tier"]&.to_sym

      transfer_result = verify_transfer_log(receipt, deposit_address, expected_amount)
      return transfer_result if transfer_result&.failure?

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
      expected_base_units = expected_amount.to_i

      matching_log = logs.find do |log|
        topics = log["topics"] || []
        next false unless topics.length >= 3
        next false unless log["address"]&.downcase == token_address.downcase
        next false unless topics[0] == TRANSFER_TOPIC

        # topics[2] is the recipient zero-padded to 32 bytes; trim and
        # normalize both sides to 40-char lowercase hex.
        log_recipient = topics[2].delete_prefix("0x").downcase.rjust(40, "0")[-40..]
        clean_deposit = deposit_address.delete_prefix("0x").downcase.rjust(40, "0")[-40..]
        next false unless log_recipient == clean_deposit

        log_amount = log["data"].delete_prefix("0x").to_i(16)
        log_amount == expected_base_units
      end

      return Result.failure("No matching Transfer event found") unless matching_log

      nil
    end
  end
end
