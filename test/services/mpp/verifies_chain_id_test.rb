# frozen_string_literal: true

require "test_helper"

# Unit tests for Mpp::VerifiesChainId. The service makes a single
# eth_chainId JSON-RPC request and compares the returned chain id to the
# one the Rails env expects (production = mainnet, anything else = Moderato
# testnet). The bug this guards against is agent-team-tv6e: a prod deploy
# shipping a mainnet token contract paired with a testnet RPC URL, which
# silently strands user payments.
class Mpp::VerifiesChainIdTest < ActiveSupport::TestCase
  MAINNET_CHAIN_ID = 4217       # 0x1079, rpc.tempo.xyz
  TESTNET_CHAIN_ID = 42431      # 0xa5bf, rpc.moderato.tempo.xyz
  MAINNET_RPC_URL  = "https://rpc.tempo.xyz"
  TESTNET_RPC_URL  = "https://rpc.moderato.tempo.xyz"

  # --- expected_chain_id_for: env → chain mapping ---

  test "expected_chain_id_for maps production to mainnet" do
    assert_equal MAINNET_CHAIN_ID,
      Mpp::VerifiesChainId.expected_chain_id_for("production")
  end

  test "expected_chain_id_for maps development to testnet" do
    assert_equal TESTNET_CHAIN_ID,
      Mpp::VerifiesChainId.expected_chain_id_for("development")
  end

  test "expected_chain_id_for maps test to testnet" do
    assert_equal TESTNET_CHAIN_ID,
      Mpp::VerifiesChainId.expected_chain_id_for("test")
  end

  test "expected_chain_id_for maps staging to testnet" do
    # Staging runs against Moderato so we can exercise the MPP flow without
    # spending real USDC.e. Any non-'production' string routes to testnet.
    assert_equal TESTNET_CHAIN_ID,
      Mpp::VerifiesChainId.expected_chain_id_for("staging")
  end

  test "expected_chain_id_for accepts an ActiveSupport::StringInquirer" do
    # Rails.env is a StringInquirer, not a bare String — confirm the .to_s
    # path works so the initializer's default wiring is correct.
    inquirer = ActiveSupport::StringInquirer.new("production")
    assert_equal MAINNET_CHAIN_ID,
      Mpp::VerifiesChainId.expected_chain_id_for(inquirer)
  end

  # --- should_run?: gate logic for the initializer ---

  test "should_run? is true in production by default" do
    assert Mpp::VerifiesChainId.should_run?(env: "production", env_vars: {}, rake_task_running: false)
  end

  test "should_run? is false in test by default" do
    # Test suite boots Rails constantly; blocking on Tempo RPC would
    # be intolerable. Default to off.
    refute Mpp::VerifiesChainId.should_run?(env: "test", env_vars: {}, rake_task_running: false)
  end

  test "should_run? is false in development by default" do
    refute Mpp::VerifiesChainId.should_run?(env: "development", env_vars: {}, rake_task_running: false)
  end

  test "should_run? is true in development when MPP_CHAINID_GUARD=1" do
    assert Mpp::VerifiesChainId.should_run?(
      env: "development",
      env_vars: { "MPP_CHAINID_GUARD" => "1" },
      rake_task_running: false
    )
  end

  test "should_run? is false in production when TEMPO_SKIP_CHAINID_GUARD=1 (emergency opt-out)" do
    refute Mpp::VerifiesChainId.should_run?(
      env: "production",
      env_vars: { "TEMPO_SKIP_CHAINID_GUARD" => "1" },
      rake_task_running: false
    )
  end

  test "should_run? is false during a rake task even in production (so asset precompile doesn't need RPC)" do
    refute Mpp::VerifiesChainId.should_run?(
      env: "production",
      env_vars: {},
      rake_task_running: true
    )
  end

  # --- bypassed?: surface the silent-skip env var (agent-team-vo2c) ---

  test "bypassed? returns true when TEMPO_SKIP_CHAINID_GUARD=1" do
    # Initializer uses this to emit a WARN log on every bypassed boot —
    # without it the env var quietly stays set post-incident.
    assert Mpp::VerifiesChainId.bypassed?(env_vars: { "TEMPO_SKIP_CHAINID_GUARD" => "1" })
  end

  test "bypassed? returns false when env var is unset" do
    refute Mpp::VerifiesChainId.bypassed?(env_vars: {})
  end

  test "bypassed? returns false for non-1 values (treats only '1' as opt-out)" do
    refute Mpp::VerifiesChainId.bypassed?(env_vars: { "TEMPO_SKIP_CHAINID_GUARD" => "true" })
    refute Mpp::VerifiesChainId.bypassed?(env_vars: { "TEMPO_SKIP_CHAINID_GUARD" => "0" })
    refute Mpp::VerifiesChainId.bypassed?(env_vars: { "TEMPO_SKIP_CHAINID_GUARD" => "" })
  end

  # --- matching chain: success ---

  test "succeeds when mainnet RPC returns mainnet chain id and prod is expected" do
    stub_eth_chain_id(MAINNET_RPC_URL, "0x1079")

    result = Mpp::VerifiesChainId.call(
      rpc_url: MAINNET_RPC_URL,
      expected_chain_id: MAINNET_CHAIN_ID
    )

    assert result.success?, "Expected mainnet-to-mainnet to succeed, got: #{result.error}"
    assert_equal MAINNET_CHAIN_ID, result.data[:chain_id]
    assert_equal MAINNET_RPC_URL, result.data[:rpc_url]
  end

  test "succeeds when testnet RPC returns testnet chain id and testnet is expected" do
    stub_eth_chain_id(TESTNET_RPC_URL, "0xa5bf")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.success?, "Expected testnet-to-testnet to succeed, got: #{result.error}"
    assert_equal TESTNET_CHAIN_ID, result.data[:chain_id]
  end

  # --- mismatch: failure (this is the test that would have caught tv6e) ---

  test "fails when testnet RPC is paired with mainnet expectation (the tv6e bug)" do
    # Simulates the original kpxs mistake: deploy.yml overrode the RPC
    # URL to Moderato (testnet) while the token contract was USDC.e
    # (mainnet only). The guard must catch this.
    stub_eth_chain_id(TESTNET_RPC_URL, "0xa5bf")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: MAINNET_CHAIN_ID
    )

    assert result.failure?, "Guard must reject testnet RPC when mainnet is expected"
    assert_match(/Chain ID mismatch/, result.error)
    assert_match(/chain #{TESTNET_CHAIN_ID}/, result.error)
    assert_match(/expects chain #{MAINNET_CHAIN_ID}/, result.error)
  end

  test "fails when mainnet RPC is paired with testnet expectation (symmetric)" do
    stub_eth_chain_id(MAINNET_RPC_URL, "0x1079")

    result = Mpp::VerifiesChainId.call(
      rpc_url: MAINNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?, "Guard must reject mainnet RPC when testnet is expected"
    assert_match(/Chain ID mismatch/, result.error)
  end

  # --- RPC transport failures: failure ---

  test "fails when the RPC returns a non-2xx response" do
    stub_request(:post, TESTNET_RPC_URL)
      .to_return(status: 502, body: "")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_match(/RPC HTTP error: 502/, result.error)
  end

  test "fails when the RPC returns a JSON-RPC error envelope" do
    stub_request(:post, TESTNET_RPC_URL).to_return(
      status: 200,
      body: { jsonrpc: "2.0", id: 1, error: { code: -32_600, message: "Invalid request" } }.to_json
    )

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_match(/RPC error: Invalid request/, result.error)
  end

  test "fails on RPC timeout (tagged as transient for fail-open)" do
    stub_request(:post, TESTNET_RPC_URL).to_timeout

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_match(/network error/, result.error)
    assert_equal :transient, result.code,
      "Net timeouts must be tagged :transient so the initializer can fail-open"
  end

  test "fails on connection refused (transient)" do
    stub_request(:post, TESTNET_RPC_URL).to_raise(Errno::ECONNREFUSED)

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_equal :transient, result.code
  end

  test "tags 5xx HTTP responses as transient" do
    # A 502/503 during a Kamal rolling deploy should not wedge boot
    # (agent-team-vo2c). The initializer downgrades :transient codes
    # to a WARN log and continues booting; only confirmed mismatches
    # fail-closed.
    stub_request(:post, TESTNET_RPC_URL)
      .to_return(status: 503, body: "")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_equal :transient, result.code
  end

  test "does not tag 4xx HTTP responses as transient (config error)" do
    # 400/404 means the URL is wrong, not a transient blip — retrying
    # won't help. Stay fail-closed so it surfaces in deploy.
    stub_request(:post, TESTNET_RPC_URL).to_return(status: 404, body: "")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    refute_equal :transient, result.code,
      "4xx is a config error, must NOT fail-open"
  end

  test "does not tag a confirmed chain mismatch as transient" do
    # Mismatch is THE bug the guard exists to catch. Must always fail-closed.
    stub_eth_chain_id(TESTNET_RPC_URL, "0xa5bf")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: MAINNET_CHAIN_ID
    )

    assert result.failure?
    refute_equal :transient, result.code,
      "Confirmed mismatch must never fail-open"
  end

  test "fails when result is missing" do
    stub_request(:post, TESTNET_RPC_URL).to_return(
      status: 200, body: { jsonrpc: "2.0", id: 1 }.to_json
    )

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_match(/empty result/, result.error)
  end

  test "fails when body is not valid JSON" do
    stub_request(:post, TESTNET_RPC_URL).to_return(status: 200, body: "<html>not json")

    result = Mpp::VerifiesChainId.call(
      rpc_url: TESTNET_RPC_URL,
      expected_chain_id: TESTNET_CHAIN_ID
    )

    assert result.failure?
    assert_match(/invalid JSON/, result.error)
  end

  private

  def stub_eth_chain_id(url, hex_result)
    stub_request(:post, url)
      .with(body: hash_including("method" => "eth_chainId"))
      .to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1, result: hex_result }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
