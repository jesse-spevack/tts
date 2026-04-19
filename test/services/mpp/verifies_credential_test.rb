# frozen_string_literal: true

require "test_helper"

class Mpp::VerifiesCredentialTest < ActiveSupport::TestCase
  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  setup do
    @amount_cents = 100
    @currency = "usd"
    @tx_hash = "0x#{SecureRandom.hex(32)}"
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"
    Stripe.api_key = "sk_test_fake"

    # Exercise the production sequencing: provision deposit address first,
    # then sign the challenge with that address as recipient, then persist
    # the MppPayment row linking challenge_id ↔ deposit_address.
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_verifies_#{SecureRandom.hex(4)}",
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
    payment_intent_id = deposit_result.data[:payment_intent_id]

    freeze_time do
      challenge_result = Mpp::GeneratesChallenge.call(
        amount_cents: @amount_cents,
        currency: @currency,
        recipient: @deposit_address,
        voice_tier: :premium
      )
      @challenge = challenge_result.data
    end

    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: @challenge[:id],
      deposit_address: @deposit_address,
      stripe_payment_intent_id: payment_intent_id,
      status: :pending
    )

    # Build a valid credential: echoed challenge fields + payment payload.
    # Payload carries only the tx hash — deposit_address is resolved from
    # the DB row by challenge_id at verification time.
    @valid_credential_hash = {
      challenge: {
        id: @challenge[:id],
        realm: @challenge[:realm],
        method: @challenge[:method],
        intent: @challenge[:intent],
        request: @challenge[:request],
        expires: @challenge[:expires]
      },
      payload: {
        type: "hash",
        hash: @tx_hash
      }
    }

    @valid_credential = Base64.strict_encode64(JSON.generate(@valid_credential_hash))
  end

  # --- HMAC verification tests ---

  test "returns failure when credential is nil" do
    result = Mpp::VerifiesCredential.call(credential: nil)

    assert result.failure?
  end

  test "returns failure when credential is empty string" do
    result = Mpp::VerifiesCredential.call(credential: "")

    assert result.failure?
  end

  test "returns failure when credential has invalid format" do
    result = Mpp::VerifiesCredential.call(credential: "not-valid-base64!!!")

    assert result.failure?
  end

  test "returns failure when credential is valid base64 but not JSON" do
    result = Mpp::VerifiesCredential.call(credential: Base64.strict_encode64("not json"))

    assert result.failure?
  end

  test "returns failure when challenge ID does not match recomputed HMAC" do
    tampered = @valid_credential_hash.deep_dup
    tampered[:challenge][:id] = "a" * 64

    credential = Base64.strict_encode64(JSON.generate(tampered))
    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
  end

  test "returns failure when challenge is expired" do
    # Generate a challenge that's already expired, signed with the same
    # deposit_address so we reach the expires check rather than failing
    # earlier on HMAC mismatch or unknown challenge.
    expired_challenge = nil
    travel_to(10.minutes.ago) do
      challenge_result = Mpp::GeneratesChallenge.call(
        amount_cents: @amount_cents,
        currency: @currency,
        recipient: @deposit_address,
        voice_tier: :premium
      )
      expired_challenge = challenge_result.data
    end

    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: expired_challenge[:id],
      deposit_address: @deposit_address,
      stripe_payment_intent_id: "pi_expired_#{SecureRandom.hex(4)}",
      status: :pending
    )

    credential_hash = {
      challenge: {
        id: expired_challenge[:id],
        realm: expired_challenge[:realm],
        method: expired_challenge[:method],
        intent: expired_challenge[:intent],
        request: expired_challenge[:request],
        expires: expired_challenge[:expires]
      },
      payload: {
        type: "hash",
        hash: @tx_hash
      }
    }
    credential = Base64.strict_encode64(JSON.generate(credential_hash))

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
  end

  test "returns failure when deposit address not found in cache" do
    # Clear the cache so the deposit address lookup fails
    Rails.cache.clear

    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure with clean error when expires is malformed (H1)" do
    bad_expires = @valid_credential_hash.deep_dup
    bad_expires[:challenge][:expires] = "not-a-timestamp"
    # Recompute HMAC for the tampered expires so we reach the parse step
    challenge = bad_expires[:challenge]
    request_json = Base64.decode64(challenge[:request])
    hmac_data = "#{challenge[:realm]}|#{challenge[:method]}|#{challenge[:intent]}|#{request_json}|#{challenge[:expires]}"
    bad_expires[:challenge][:id] = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

    credential = Base64.strict_encode64(JSON.generate(bad_expires))
    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/Invalid expires timestamp/, result.error)
  end

  test "returns failure with clean error when expires is nil (H1)" do
    bad_expires = @valid_credential_hash.deep_dup
    bad_expires[:challenge][:expires] = nil
    challenge = bad_expires[:challenge]
    request_json = Base64.decode64(challenge[:request])
    hmac_data = "#{challenge[:realm]}|#{challenge[:method]}|#{challenge[:intent]}|#{request_json}|"
    bad_expires[:challenge][:id] = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

    credential = Base64.strict_encode64(JSON.generate(bad_expires))
    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/Invalid expires timestamp/, result.error)
  end

  # --- On-chain verification tests ---

  test "returns failure when tx_hash is missing from payload" do
    no_hash = @valid_credential_hash.deep_dup
    no_hash[:payload].delete(:hash)

    credential = Base64.strict_encode64(JSON.generate(no_hash))
    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
  end

  test "returns failure when Tempo RPC returns error (hash shape)" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        error: { code: -32_000, message: "Internal error" }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
    assert_match(/Internal error/, result.error)
  end

  test "returns failure when RPC error body is a string, not a hash (H3)" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        error: "rate limited"
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
    assert_match(/rate limited/, result.error)
  end

  test "returns failure when RPC returns non-2xx HTTP status (H3)" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 502, body: "Bad Gateway")

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
    assert_match(/502/, result.error)
  end

  test "returns failure on RPC open timeout (H2)" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL).to_timeout

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
    assert_match(/timeout/i, result.error)
  end

  test "returns failure when RPC returns unparseable body (H3)" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: "<html>error</html>")

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure when transaction not found with null receipt" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: nil
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure when transaction reverted with status not 0x1" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x0",
          logs: []
        }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure when no matching Transfer event in logs" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x1",
          logs: []
        }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure when Transfer event has wrong recipient" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x1",
          logs: [
            {
              address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
              topics: [
                TRANSFER_TOPIC,
                pad_address("0xsender"),
                pad_address("0xwrong_recipient")
              ],
              data: amount_to_hex(@amount_cents)
            }
          ]
        }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure when Transfer event has wrong amount" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x1",
          logs: [
            {
              address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
              topics: [
                TRANSFER_TOPIC,
                pad_address("0xsender"),
                pad_address(@deposit_address)
              ],
              data: amount_to_hex(9999)
            }
          ]
        }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns failure when Transfer event has wrong token contract" do
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x1",
          logs: [
            {
              address: "0xwrongtoken0000000000000000000000000000",
              topics: [
                TRANSFER_TOPIC,
                pad_address("0xsender"),
                pad_address(@deposit_address)
              ],
              data: amount_to_hex(@amount_cents)
            }
          ]
        }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "returns success when all verification passes" do
    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.success?
  end

  test "successful result includes tx_hash" do
    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert_equal @tx_hash, result.data[:tx_hash]
  end

  test "successful result includes amount" do
    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    # Amount in the result is now in token base units (string from challenge)
    decimals = AppConfig::Mpp::TEMPO_TOKEN_DECIMALS
    expected_base_units = (@amount_cents * (10**decimals)) / 100
    assert_equal expected_base_units.to_s, result.data[:amount]
  end

  test "successful result includes voice_tier extracted from the challenge" do
    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    # Legacy test setup uses GeneratesChallenge's default tier (:premium).
    # agent-team-nkz.3 will route tier from the request's resolved voice
    # and compare it against this extracted value.
    assert_equal :premium, result.data[:voice_tier]
  end

  test "successful result includes recipient" do
    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert_equal @deposit_address, result.data[:recipient]
  end

  test "successful result includes challenge_id" do
    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert_equal @challenge[:id], result.data[:challenge_id]
  end

  # --- Replay protection tests ---

  test "returns failure when tx_hash already used" do
    # Create an existing MppPayment with the same tx_hash
    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      tx_hash: @tx_hash,
      status: :completed
    )

    stub_tempo_rpc_success

    result = Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert result.failure?
  end

  test "does not create or update MppPayment rows (pure verification)" do
    stub_tempo_rpc_success

    assert_no_difference "MppPayment.count" do
      Mpp::VerifiesCredential.call(credential: @valid_credential)
    end
  end

  # --- Integration test: CreatesDepositAddress → GeneratesChallenge → VerifiesCredential ---

  test "integration: deposit address flows from Stripe → challenge → verifier" do
    Stripe.api_key = "sk_test_fake"
    integration_deposit_address = "0xintegration#{SecureRandom.hex(16)}"

    Rails.cache.clear

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_integration_#{SecureRandom.hex(4)}",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: integration_deposit_address }
            }
          }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Production sequencing: deposit address first, then sign challenge
    # with it as recipient, then persist the MppPayment row.
    deposit_result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )
    payment_intent_id = deposit_result.data[:payment_intent_id]

    challenge = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: integration_deposit_address,
      voice_tier: :premium
    ).data

    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: challenge[:id],
      deposit_address: integration_deposit_address,
      stripe_payment_intent_id: payment_intent_id,
      status: :pending
    )

    credential_hash = {
      challenge: {
        id: challenge[:id],
        realm: challenge[:realm],
        method: challenge[:method],
        intent: challenge[:intent],
        request: challenge[:request],
        expires: challenge[:expires]
      },
      payload: {
        type: "hash",
        hash: "0x#{SecureRandom.hex(32)}"
      }
    }
    credential = Base64.strict_encode64(JSON.generate(credential_hash))

    # Stub the Tempo RPC with a matching Transfer event
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x1",
          logs: [
            {
              address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
              topics: [
                TRANSFER_TOPIC,
                pad_address("0xsender"),
                pad_address(integration_deposit_address)
              ],
              data: amount_to_hex(@amount_cents)
            }
          ]
        }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.success?, "Integration verification failed: #{result.error}"
    assert_equal integration_deposit_address, result.data[:recipient]
  end

  # --- RPC request format test ---

  test "sends correct JSON-RPC request to Tempo RPC endpoint" do
    stub_tempo_rpc_success

    Mpp::VerifiesCredential.call(credential: @valid_credential)

    assert_requested(:post, AppConfig::Mpp::TEMPO_RPC_URL) { |req|
      body = JSON.parse(req.body)
      body["jsonrpc"] == "2.0" &&
        body["method"] == "eth_getTransactionReceipt" &&
        body["params"] == [ @tx_hash ] &&
        body["id"] == 1
    }
  end

  # --- Signature credential tests ---

  test "signature: submits raw transaction and returns success with tx hash" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    submitted_tx_hash = "0x#{SecureRandom.hex(32)}"
    stub_send_raw_transaction(result: submitted_tx_hash)
    stub_get_transaction_receipt(submitted_tx_hash, receipt: valid_receipt(submitted_tx_hash))

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.success?, "Expected success but got: #{result.error}"
    assert_equal submitted_tx_hash, result.data[:tx_hash]
  end

  test "signature: polls for receipt when first attempt returns null, succeeds on retry" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    submitted_tx_hash = "0x#{SecureRandom.hex(32)}"
    stub_send_raw_transaction(result: submitted_tx_hash)

    # First receipt call returns null, second returns real receipt
    receipt_stub = stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .with(body: hash_including("method" => "eth_getTransactionReceipt"))
      .to_return(
        { status: 200, body: { jsonrpc: "2.0", id: 1, result: nil }.to_json },
        { status: 200, body: { jsonrpc: "2.0", id: 1, result: valid_receipt(submitted_tx_hash) }.to_json }
      )

    service = Mpp::VerifiesCredential.new(credential: credential)
    service.define_singleton_method(:sleep) { |_| } # no-op sleep
    result = service.call

    assert result.success?, "Expected success but got: #{result.error}"
    assert_equal submitted_tx_hash, result.data[:tx_hash]

    # Verify receipt endpoint was called at least twice
    assert_requested(receipt_stub, times: 2)
  end

  test "signature: returns failure when eth_sendRawTransaction returns RPC error" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .with(body: hash_including("method" => "eth_sendRawTransaction"))
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        error: { code: -32_000, message: "nonce too low" }
      }.to_json)

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/nonce too low/, result.error)
  end

  test "signature: returns failure when poll for receipt times out" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    submitted_tx_hash = "0x#{SecureRandom.hex(32)}"
    stub_send_raw_transaction(result: submitted_tx_hash)

    # Receipt always returns null — simulates tx never mined
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .with(body: hash_including("method" => "eth_getTransactionReceipt"))
      .to_return(status: 200, body: { jsonrpc: "2.0", id: 1, result: nil }.to_json)

    service = Mpp::VerifiesCredential.new(credential: credential)
    service.define_singleton_method(:sleep) { |_| } # no-op sleep
    result = service.call

    assert result.failure?
    assert_match(/Transaction not found/, result.error)
  end

  test "signature: returns failure when submitted transaction reverts" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    submitted_tx_hash = "0x#{SecureRandom.hex(32)}"
    stub_send_raw_transaction(result: submitted_tx_hash)
    stub_get_transaction_receipt(submitted_tx_hash, receipt: {
      status: "0x0",
      logs: []
    })

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/Transaction reverted/, result.error)
  end

  test "signature: replay protection rejects already-used tx hash" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    submitted_tx_hash = "0x#{SecureRandom.hex(32)}"
    stub_send_raw_transaction(result: submitted_tx_hash)

    # Pre-create a payment with the same tx hash
    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      tx_hash: submitted_tx_hash,
      status: :completed
    )

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/Transaction already used/, result.error)
  end

  test "signature: transfer event log verification works after receipt obtained" do
    credential = build_signature_credential(@challenge, signature: "0xsigned_tx_data")

    submitted_tx_hash = "0x#{SecureRandom.hex(32)}"
    stub_send_raw_transaction(result: submitted_tx_hash)

    # Receipt with wrong recipient in Transfer log
    stub_get_transaction_receipt(submitted_tx_hash, receipt: {
      status: "0x1",
      logs: [
        {
          address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
          topics: [
            TRANSFER_TOPIC,
            pad_address("0xsender"),
            pad_address("0xwrong_recipient")
          ],
          data: amount_to_hex(@amount_cents)
        }
      ]
    })

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/No matching Transfer event found/, result.error)
  end

  private

  def build_signature_credential(challenge, signature:)
    credential_hash = {
      challenge: {
        id: challenge[:id],
        realm: challenge[:realm],
        method: challenge[:method],
        intent: challenge[:intent],
        request: challenge[:request],
        expires: challenge[:expires]
      },
      payload: {
        type: "signature",
        signature: signature
      }
    }
    Base64.strict_encode64(JSON.generate(credential_hash))
  end

  def stub_send_raw_transaction(result:)
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .with(body: hash_including("method" => "eth_sendRawTransaction"))
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: result
      }.to_json)
  end

  def stub_get_transaction_receipt(_tx_hash, receipt:)
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .with(body: hash_including("method" => "eth_getTransactionReceipt"))
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: receipt
      }.to_json)
  end

  def valid_receipt(_tx_hash = nil)
    {
      status: "0x1",
      logs: [
        {
          address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
          topics: [
            TRANSFER_TOPIC,
            pad_address("0xsender"),
            pad_address(@deposit_address)
          ],
          data: amount_to_hex(@amount_cents)
        }
      ]
    }
  end

  def stub_tempo_rpc_success
    stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
      .to_return(status: 200, body: {
        jsonrpc: "2.0",
        id: 1,
        result: {
          status: "0x1",
          logs: [
            {
              address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
              topics: [
                TRANSFER_TOPIC,
                pad_address("0xsender"),
                pad_address(@deposit_address)
              ],
              data: amount_to_hex(@amount_cents)
            }
          ]
        }
      }.to_json)
  end

  # Pad an address to 32 bytes (64 hex chars) as Ethereum log topics
  def pad_address(address)
    clean = address.delete_prefix("0x").downcase
    "0x" + clean.rjust(64, "0")
  end

  # Convert a cents value to the 32-byte hex uint256 the on-chain Transfer
  # event's `data` field carries. Matches the production conversion:
  # cents -> fiat USD -> token base units (6 decimals).
  def amount_to_hex(amount_cents)
    base_units = (amount_cents * (10**AppConfig::Mpp::TEMPO_TOKEN_DECIMALS)) / 100
    "0x" + base_units.to_s(16).rjust(64, "0")
  end
end
