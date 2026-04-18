# frozen_string_literal: true

require "test_helper"

class MppPayableEnqueueTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  setup do
    @valid_params = {
      source_type: "url",
      title: "Test Article",
      url: "https://example.com/article"
    }

    @amount_cents = AppConfig::Mpp::PRICE_CENTS
    @currency = AppConfig::Mpp::CURRENCY
    @tx_hash = "0x#{SecureRandom.hex(32)}"
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"

    Stripe.api_key = "sk_test_fake"
    stub_stripe_deposit_address(address: @deposit_address)
  end

  test "enqueues ProcessesNarrationJob when anonymous narration is created" do
    credential = valid_credential
    stub_tempo_rpc_success

    assert_enqueued_with(job: ProcessesNarrationJob) do
      post api_v1_episodes_path,
        params: @valid_params,
        headers: { "Authorization" => "Payment #{credential}" },
        as: :json
    end

    assert_response :created
  end

  test "does not enqueue ProcessesNarrationJob for authenticated episode creation" do
    subscriber = users(:subscriber)
    token = GeneratesApiToken.call(user: subscriber)

    assert_no_enqueued_jobs(only: ProcessesNarrationJob) do
      post api_v1_episodes_path,
        params: {
          source_type: "extension",
          title: "Test Article",
          author: "Test Author",
          description: "A test article description",
          content: "This is the full content of the article. " * 50,
          url: "https://example.com/article"
        },
        headers: { "Authorization" => "Bearer #{token.plain_token}" },
        as: :json
    end
  end

  private

  def provision_challenge(deposit_address: @deposit_address)
    Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    challenge = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: deposit_address
    ).data

    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: challenge[:id],
      deposit_address: deposit_address,
      stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
      status: :pending
    )

    challenge
  end

  def valid_credential
    challenge = provision_challenge

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
        hash: @tx_hash
      }
    }

    Base64.strict_encode64(JSON.generate(credential_hash))
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

  def stub_stripe_deposit_address(address:)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_#{SecureRandom.hex(8)}",
        object: "payment_intent",
        amount: @amount_cents,
        currency: @currency,
        status: "requires_action",
        next_action: {
          type: "crypto_display_details",
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: address }
            }
          }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })
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
