# frozen_string_literal: true

require "test_helper"

# Verifies the MPP flow when challenges are signed under USDC.e (Stripe's
# mainnet guidance) rather than pathUSD (testnet default). Tests inject
# token_address: into GeneratesChallenge to control the signed currency;
# VerifiesCredential filters Transfer events against the signed value
# regardless of TEMPO_CURRENCY_TOKEN env.
class Mpp::VerifiesCredentialUsdcETest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  # Canonical addresses from Stripe's MPP docs:
  PATH_USD_CONTRACT = "0x20c0000000000000000000000000000000000000"
  USDC_E_CONTRACT   = "0x20c000000000000000000000b9537d11c60e8b50"

  setup do
    @amount_cents = 150          # matches MPP Premium tier ($1.50)
    @amount_base_units = "1500000" # $1.50 at 6 decimals, what the challenge carries
    @currency = "usd"
    @tx_hash = "0x#{SecureRandom.hex(32)}"
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"
    Stripe.api_key = "sk_test_fake"

    # Standard MPP setup: create deposit address via stubbed Stripe, then sign
    # the challenge against that address and persist the MppPayment row.
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: stripe_response_body(@deposit_address, USDC_E_CONTRACT),
                 headers: { "Content-Type" => "application/json" })

    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: USDC_E_CONTRACT
    )
    @payment_intent_id = deposit_result.data[:payment_intent_id]

    challenge_result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      recipient: @deposit_address,
      voice_tier: :premium,
      token_address: USDC_E_CONTRACT
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

  test "verifier filters Transfer events by the USDC.e contract when challenge was signed under USDC.e" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: rpc_receipt_body(token_address: USDC_E_CONTRACT))

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.success?, "Expected USDC.e Transfer to be accepted, got: #{result.error}"
  end

  test "accepts a Transfer event whose log address matches the signed USDC.e currency" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: rpc_receipt_body(token_address: USDC_E_CONTRACT))

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.success?, "USDC.e Transfer should credit the payment"
    assert_equal @tx_hash, result.data[:tx_hash]
    assert_equal @deposit_address, result.data[:recipient]
  end

  test "accepts USDC.e when the contract address is uppercase (case-insensitive match)" do
    upper = USDC_E_CONTRACT.upcase.sub(/\A0X/, "0x")
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: rpc_receipt_body(token_address: upper))

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.success?,
      "Case of log address must not affect acceptance: #{result.error}"
  end

  test "rejects a pathUSD Transfer event when challenge was signed under USDC.e" do
    # User sends the wrong token (cached wallet config, old docs) — must reject.
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: rpc_receipt_body(token_address: PATH_USD_CONTRACT))

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?,
      "pathUSD Transfer must be rejected when challenge was signed for USDC.e"
    assert_match(/No matching Transfer event/, result.error,
      "Rejection reason should indicate no matching Transfer log")
  end

  test "verifier honors signed pathUSD currency even when env is currently USDC.e (rollback safety)" do
    # Challenge issued under pathUSD, operator flips TEMPO_CURRENCY_TOKEN
    # to USDC.e mid-TTL, user submits. Verifier must honor signed currency
    # (pathUSD), not env. Otherwise the in-flight payment strands.
    deposit_address = "0xrollback#{SecureRandom.hex(16)}"

    # Provision deposit address against the OLD (pathUSD) supported_tokens.
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: stripe_response_body(deposit_address, PATH_USD_CONTRACT))

    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents, currency: @currency,
      expected_token_address: PATH_USD_CONTRACT
    )

    # Sign the challenge under pathUSD (the pre-rollback token).
    challenge = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      recipient: deposit_address, voice_tier: :premium,
      token_address: PATH_USD_CONTRACT
    ).data

    MppPayment.create!(
      amount_cents: @amount_cents, currency: @currency,
      challenge_id: challenge[:id], deposit_address: deposit_address,
      stripe_payment_intent_id: deposit_result.data[:payment_intent_id],
      status: :pending
    )

    credential = Base64.strict_encode64(JSON.generate(
      challenge: challenge.slice(:id, :realm, :method, :intent, :request, :expires),
      payload: { type: "hash", hash: @tx_hash }
    ))

    # Simulate env flip: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN now reports
    # USDC.e, but the on-chain Transfer was for pathUSD (matching the
    # signed currency). Swap the constant to make the env-flip explicit;
    # the verifier must NOT consult it.
    stub_const(AppConfig::Mpp, :TEMPO_CURRENCY_TOKEN, USDC_E_CONTRACT) do
      stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
        .to_return(status: 200, body: rpc_receipt_body(
          token_address: PATH_USD_CONTRACT,
          deposit_address: deposit_address
        ))

      result = Mpp::VerifiesCredential.call(credential: credential)

      assert result.success?,
        "Verifier must honor the signed pathUSD currency post-rollback, got: #{result.error}"
    end
  end

  test "rejects challenge whose signed currency is not a string (type-guard)" do
    # Generator bug or leaked secret could surface a non-string here.
    # Verifier must clean-reject, not crash on .present? / .downcase.
    [ nil, 42, { "x" => 1 }, [], true ].each do |bad_currency|
      credential = forge_credential_with_currency(bad_currency)
      result = Mpp::VerifiesCredential.call(credential: credential)
      assert result.failure?, "Expected failure for currency=#{bad_currency.inspect}"
      assert_match(/missing or invalid currency/, result.error,
        "Expected clean rejection for currency=#{bad_currency.inspect}, got: #{result.error}")
    end
  end

  test "rejects challenge whose signed currency is not in the allowlist" do
    # Even with HMAC binding, an off-allowlist value must not let the
    # verifier query an arbitrary contract.
    unknown_token = "0xdeadbeefcafef00d000000000000000000000000"
    deposit_address = "0xunknown#{SecureRandom.hex(16)}"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: stripe_response_body(deposit_address, unknown_token))

    # Pass matching expected_token_address so CreatesDepositAddress doesn't
    # block here — we're testing the verifier's allowlist downstream.
    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents, currency: @currency,
      expected_token_address: unknown_token
    )

    challenge = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      recipient: deposit_address, voice_tier: :premium,
      token_address: unknown_token
    ).data

    MppPayment.create!(
      amount_cents: @amount_cents, currency: @currency,
      challenge_id: challenge[:id], deposit_address: deposit_address,
      stripe_payment_intent_id: deposit_result.data[:payment_intent_id],
      status: :pending
    )

    credential = Base64.strict_encode64(JSON.generate(
      challenge: challenge.slice(:id, :realm, :method, :intent, :request, :expires),
      payload: { type: "hash", hash: @tx_hash }
    ))

    # No RPC stub needed — we should reject before getting that far.
    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?, "Unknown signed currency must be rejected"
    assert_match(/Unsupported challenge currency/, result.error)
  end

  test "Standard tier $0.75 (750000 base units) verifies against USDC.e" do
    # 75 cents * 10^6 / 100 = 750_000 base units. Both tokens are 6 decimals.
    amount_cents = 75
    deposit_address = "0xstd#{SecureRandom.hex(16)}"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: stripe_response_body(deposit_address, USDC_E_CONTRACT))

    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: amount_cents, currency: @currency,
      expected_token_address: USDC_E_CONTRACT
    )
    challenge = Mpp::GeneratesChallenge.call(
      amount_cents: amount_cents,
      recipient: deposit_address, voice_tier: :standard,
      token_address: USDC_E_CONTRACT
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

  test "TEMPO_CURRENCY_TOKEN default stays pathUSD (testnet safe)" do
    # Default must stay pathUSD; prod opts into USDC.e via deploy config.
    assert_equal PATH_USD_CONTRACT, AppConfig::Mpp::TEMPO_CURRENCY_TOKEN
  end

  test "TEMPO_RPC_URL default points at rpc.moderato.tempo.xyz (not the legacy testnet alias)" do
    # testnet.tempo.xyz is a legacy alias; default to canonical host so
    # eventual DNS deprecation doesn't surprise us.
    assert_equal "https://rpc.moderato.tempo.xyz", AppConfig::Mpp::TEMPO_RPC_URL
  end

  private

  # Build a Transfer-log RPC receipt. Override token_address to simulate
  # right-token / wrong-token scenarios.
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

  # Stripe PaymentIntent shape including supported_tokens, so the
  # contract-address assertion in CreatesDepositAddress sees a match.
  def stripe_response_body(deposit_address, token_contract_address)
    {
      id: "pi_usdc_#{SecureRandom.hex(4)}",
      next_action: {
        crypto_display_details: {
          deposit_addresses: {
            tempo: {
              address: deposit_address,
              supported_tokens: [
                { token_currency: "usdc", token_contract_address: token_contract_address }
              ]
            }
          }
        }
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

  # Forge a credential with arbitrary `currency`, HMAC-signed with the
  # real secret. Bypasses GeneratesChallenge so we can exercise the
  # verifier's type-guard with values the generator wouldn't produce.
  def forge_credential_with_currency(currency_value)
    realm = AppConfig::Domain::HOST
    method = "tempo"
    intent = "charge"
    request_json = JSON.generate(
      amount: @amount_base_units,
      currency: currency_value,
      recipient: @deposit_address,
      voice_tier: "premium"
    )
    request_b64 = Base64.strict_encode64(request_json)
    expires = (Time.current + AppConfig::Mpp::CHALLENGE_TTL_SECONDS).iso8601
    hmac_data = "#{realm}|#{method}|#{intent}|#{request_json}|#{expires}"
    id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

    MppPayment.create!(
      amount_cents: @amount_cents, currency: @currency, challenge_id: id,
      deposit_address: @deposit_address,
      stripe_payment_intent_id: "pi_forged_#{SecureRandom.hex(4)}",
      status: :pending
    )

    Base64.strict_encode64(JSON.generate(
      challenge: { id: id, realm: realm, method: method, intent: intent, request: request_b64, expires: expires },
      payload: { type: "hash", hash: @tx_hash }
    ))
  end
end
