# frozen_string_literal: true

require "test_helper"

# Tests that the MPP verification flow works correctly when TEMPO_CURRENCY_TOKEN
# is configured to USDC.e (0x20c000000000000000000000b9537d11c60e8b50), which
# is Stripe's prod guidance for mainnet traffic, rather than pathUSD (the
# testnet default 0x20c0000000000000000000000000000000000000).
#
# Scope: agent-team-arak (swap MPP production payment token to USDC.e).
# These tests exercise the env-gated code path via swap_currency_token to
# simulate prod without mutating the frozen AppConfig constant permanently.
class Mpp::VerifiesCredentialUsdcETest < ActiveSupport::TestCase
  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  # Canonical addresses from Stripe's MPP docs:
  PATH_USD_CONTRACT = "0x20c0000000000000000000000000000000000000"
  USDC_E_CONTRACT   = "0x20c000000000000000000000b9537d11c60e8b50"

  setup do
    @amount_cents = 100          # matches GeneratesChallenge default tier
    @amount_base_units = "1000000" # $1 at 6 decimals, what the challenge carries
    @currency = "usd"
    @tx_hash = "0x#{SecureRandom.hex(32)}"
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"
    Stripe.api_key = "sk_test_fake"

    # Standard MPP setup: create deposit address via stubbed Stripe, then sign
    # the challenge against that address and persist the MppPayment row.
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_usdc_#{SecureRandom.hex(4)}",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: @deposit_address }
            }
          }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )
    @payment_intent_id = deposit_result.data[:payment_intent_id]

    challenge_result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @deposit_address,
      voice_tier: :premium
    )
    @challenge = challenge_result.data

    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: @challenge[:id],
      deposit_address: @deposit_address,
      stripe_payment_intent_id: @payment_intent_id,
      status: :pending
    )

    @valid_credential = Base64.strict_encode64(JSON.generate(
      challenge: {
        id: @challenge[:id],
        realm: @challenge[:realm],
        method: @challenge[:method],
        intent: @challenge[:intent],
        request: @challenge[:request],
        expires: @challenge[:expires]
      },
      payload: { type: "hash", hash: @tx_hash }
    ))
  end

  # --- 1. Token-filter-respects-env ---

  test "verifier filters Transfer events by the USDC.e contract when env is USDC.e" do
    swap_currency_token(USDC_E_CONTRACT) do
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(token_address: USDC_E_CONTRACT))

      result = Mpp::VerifiesCredential.call(credential: @valid_credential)

      assert result.success?, "Expected USDC.e Transfer to be accepted, got: #{result.error}"
    end
  end

  # --- 2. Correct-token accepted (USDC.e) ---

  test "accepts a Transfer event whose log address matches the USDC.e env" do
    swap_currency_token(USDC_E_CONTRACT) do
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(token_address: USDC_E_CONTRACT))

      result = Mpp::VerifiesCredential.call(credential: @valid_credential)

      assert result.success?, "USDC.e Transfer should credit the payment"
      assert_equal @tx_hash, result.data[:tx_hash]
      assert_equal @deposit_address, result.data[:recipient]
    end
  end

  test "accepts USDC.e when the contract address is uppercase (case-insensitive match)" do
    swap_currency_token(USDC_E_CONTRACT) do
      upper = USDC_E_CONTRACT.upcase.sub(/\A0X/, "0x")
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(token_address: upper))

      result = Mpp::VerifiesCredential.call(credential: @valid_credential)

      assert result.success?,
        "Case of log address must not affect acceptance: #{result.error}"
    end
  end

  # --- 3. Wrong-token rejected (critical safety) ---

  test "rejects a pathUSD Transfer event when env is configured for USDC.e" do
    # Prod safety: once TEMPO_CURRENCY_TOKEN flips to USDC.e, a user who
    # accidentally sends pathUSD (old docs, cached wallet config) must NOT
    # be silently credited. The verifier has to reject it.
    swap_currency_token(USDC_E_CONTRACT) do
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(token_address: PATH_USD_CONTRACT))

      result = Mpp::VerifiesCredential.call(credential: @valid_credential)

      assert result.failure?,
        "pathUSD Transfer must be rejected when env is USDC.e — current env: #{AppConfig::Mpp::TEMPO_CURRENCY_TOKEN}"
      assert_match(/No matching Transfer event/, result.error,
        "Rejection reason should indicate no matching Transfer log")
    end
  end

  test "rejects USDC.e Transfer when env is still pathUSD (symmetric safety)" do
    # Mirror of the above — proves the filter is symmetric and there is no
    # hidden 'accept anything starting with 0x20c0' shortcut.
    swap_currency_token(PATH_USD_CONTRACT) do
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(token_address: USDC_E_CONTRACT))

      result = Mpp::VerifiesCredential.call(credential: @valid_credential)

      assert result.failure?, "USDC.e Transfer must be rejected when env is pathUSD"
      assert_match(/No matching Transfer event/, result.error)
    end
  end

  # --- 4. Decimals unchanged across the swap ---

  test "Standard tier $0.75 (750000 base units) verifies against USDC.e" do
    # Standard tier price = 75 cents. Challenge amount is in base units:
    # 75 cents * 10^6 / 100 = 750_000. Swap must not break this math.
    amount_cents = 75
    deposit_address = "0xstd#{SecureRandom.hex(16)}"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_std_#{SecureRandom.hex(4)}",
        next_action: {
          crypto_display_details: {
            deposit_addresses: { tempo: { address: deposit_address } }
          }
        }
      }.to_json)

    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: amount_cents, currency: @currency
    )
    challenge = Mpp::GeneratesChallenge.call(
      amount_cents: amount_cents, currency: @currency,
      recipient: deposit_address, voice_tier: :standard
    ).data

    MppPayment.create!(
      amount_cents: amount_cents, currency: @currency,
      challenge_id: challenge[:id], deposit_address: deposit_address,
      stripe_payment_intent_id: deposit_result.data[:payment_intent_id],
      status: :pending
    )

    credential = Base64.strict_encode64(JSON.generate(
      challenge: challenge.slice(:id, :realm, :method, :intent, :request, :expires),
      payload: { type: "hash", hash: @tx_hash }
    ))

    swap_currency_token(USDC_E_CONTRACT) do
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(
          token_address: USDC_E_CONTRACT,
          deposit_address: deposit_address,
          amount_cents: amount_cents
        ))

      result = Mpp::VerifiesCredential.call(credential: credential)

      assert result.success?,
        "Standard tier $0.75 in USDC.e should verify (both tokens are 6 decimals): #{result.error}"
      assert_equal "750000", result.data[:amount],
        "amount in result should still be 750000 base units"
    end
  end

  # --- 5. Default + RPC URL expectations for Implementer (agent-team-kpxs) ---

  test "TEMPO_CURRENCY_TOKEN default stays pathUSD (testnet safe)" do
    # Even after kpxs, the library default must stay pathUSD so testnet
    # and dev environments keep working without a new env override.
    # Prod gets USDC.e via an explicit env var in the deploy config.
    assert_equal PATH_USD_CONTRACT, AppConfig::Mpp::TEMPO_CURRENCY_TOKEN
  end

  test "TEMPO_RPC_URL default points at rpc.moderato.tempo.xyz (not the legacy testnet alias)" do
    # Researcher (agent-team-nukj) confirmed testnet.tempo.xyz is a legacy
    # alias for rpc.moderato.tempo.xyz (both resolve to chain 42431). The
    # default should be the canonical host so future DNS deprecation of the
    # alias doesn't take prod down. Currently fails — Implementer will fix
    # in agent-team-kpxs by changing app/models/app_config.rb:151.
    assert_equal "https://rpc.moderato.tempo.xyz", AppConfig::Mpp::TEMPO_RPC_URL
  end

  private

  # Swap AppConfig::Mpp::TEMPO_CURRENCY_TOKEN for the duration of a block.
  # Restores the original value on exit (including on exception) so parallel
  # tests don't leak state.
  def swap_currency_token(new_value)
    original = AppConfig::Mpp::TEMPO_CURRENCY_TOKEN
    AppConfig::Mpp.send(:remove_const, :TEMPO_CURRENCY_TOKEN)
    AppConfig::Mpp.const_set(:TEMPO_CURRENCY_TOKEN, new_value)
    yield
  ensure
    AppConfig::Mpp.send(:remove_const, :TEMPO_CURRENCY_TOKEN)
    AppConfig::Mpp.const_set(:TEMPO_CURRENCY_TOKEN, original)
  end

  # Build a JSON-RPC eth_getTransactionReceipt response with a single
  # Transfer log. Defaults match the fixture setup; override the token
  # address to simulate wrong-token-sent or right-token-sent scenarios.
  def rpc_receipt_body(token_address:, deposit_address: @deposit_address, amount_cents: @amount_cents)
    {
      jsonrpc: "2.0",
      id: 1,
      result: {
        status: "0x1",
        logs: [
          {
            address: token_address,
            topics: [
              TRANSFER_TOPIC,
              pad_address("0xsender"),
              pad_address(deposit_address)
            ],
            data: amount_to_hex(amount_cents)
          }
        ]
      }
    }.to_json
  end

  def pad_address(address)
    clean = address.delete_prefix("0x").downcase
    "0x" + clean.rjust(64, "0")
  end

  def amount_to_hex(amount_cents)
    base_units = (amount_cents * (10**AppConfig::Mpp::TEMPO_TOKEN_DECIMALS)) / 100
    "0x" + base_units.to_s(16).rjust(64, "0")
  end
end
