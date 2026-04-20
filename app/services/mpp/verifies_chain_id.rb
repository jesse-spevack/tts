# frozen_string_literal: true

require "net/http"

module Mpp
  # Boot-time guard that the configured Tempo RPC URL actually points at
  # the chain we expect. Catches the specific class of bug where a testnet
  # RPC is paired with a mainnet token contract (or vice versa), which
  # silently strands user payments.
  #
  # Returns Result.success when the chain matches; Result.failure on
  # mismatch, RPC error, or timeout. The initializer translates failure
  # into a loud boot abort in production.
  class VerifiesChainId
    # Tempo chain IDs, confirmed via eth_chainId on 2026-04-20:
    #   rpc.tempo.xyz          -> 0x1079 = 4217  (mainnet)
    #   rpc.moderato.tempo.xyz -> 0xa5bf = 42431 (Moderato testnet)
    MAINNET_CHAIN_ID = 4217
    TESTNET_CHAIN_ID = 42431

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      rpc_url: AppConfig::Mpp::TEMPO_RPC_URL,
      expected_chain_id: self.class.expected_chain_id_for(Rails.env)
    )
      @rpc_url = rpc_url
      @expected_chain_id = expected_chain_id
    end

    # Picks the expected chain based on Rails env. Production must see
    # mainnet; every other env (dev, test, staging, ci) must see testnet.
    def self.expected_chain_id_for(env)
      env.to_s == "production" ? MAINNET_CHAIN_ID : TESTNET_CHAIN_ID
    end

    # Whether the boot-time guard should actually run. Production: on by
    # default. Other envs: off unless MPP_CHAINID_GUARD=1 is set. All envs:
    # off when TEMPO_SKIP_CHAINID_GUARD=1 or during a rake task (so asset
    # precompile / migrations don't require Tempo RPC reachability).
    # Kept here (not in the initializer) so the gate is unit-testable.
    def self.should_run?(env: Rails.env, env_vars: ENV, rake_task_running: rake_task_running?)
      return false if env_vars["TEMPO_SKIP_CHAINID_GUARD"] == "1"
      return false if rake_task_running
      return true  if env.to_s == "production"
      env_vars["MPP_CHAINID_GUARD"] == "1"
    end

    def self.rake_task_running?
      defined?(Rake.application) && Rake.application.top_level_tasks.any?
    end

    def call
      chain_id = fetch_chain_id
      return chain_id if chain_id.is_a?(Result) && chain_id.failure?

      if chain_id == expected_chain_id
        Result.success(chain_id: chain_id, rpc_url: rpc_url)
      else
        Result.failure(
          "Chain ID mismatch: #{rpc_url} reports chain #{chain_id} " \
          "but this Rails env (#{Rails.env}) expects chain #{expected_chain_id}. " \
          "Likely cause: TEMPO_RPC_URL and TEMPO_CURRENCY_TOKEN point at different chains."
        )
      end
    end

    private

    attr_reader :rpc_url, :expected_chain_id

    def fetch_chain_id
      uri = URI(rpc_url)
      request_body = { jsonrpc: "2.0", method: "eth_chainId", params: [], id: 1 }.to_json

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

      hex = body["result"]
      return Result.failure("RPC returned empty result") if hex.nil? || hex.empty?

      Integer(hex, 16)
    rescue Net::OpenTimeout, Net::ReadTimeout
      Result.failure("RPC timeout")
    rescue JSON::ParserError
      Result.failure("RPC returned invalid JSON")
    rescue ArgumentError
      Result.failure("RPC returned non-hex chain id: #{body && body["result"]}")
    end
  end
end
