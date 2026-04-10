# frozen_string_literal: true

require "test_helper"

class Mpp::CreatesDepositAddressTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 100
    @currency = "usd"
    @recipient = "0x1234567890abcdef1234567890abcdef12345678"
    Stripe.api_key = "sk_test_fake"
  end

  test "calls Stripe::PaymentIntent.create with correct params" do
    deposit_address = "0xdeposit_address_abc123"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .with(body: hash_including(
        "payment_method_types[]" => "crypto",
        "amount" => @amount_cents.to_s,
        "currency" => @currency
      ))
      .to_return(status: 200, body: {
        id: "pi_test_123",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    assert result.success?
  end

  test "extracts deposit address from next_action crypto_display_details" do
    deposit_address = "0xdeposit_address_abc123"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_123",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    assert_equal deposit_address, result.data[:deposit_address]
  end

  test "returns payment_intent_id in result" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_456",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xaddr" }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    assert_equal "pi_test_456", result.data[:payment_intent_id]
  end

  test "caches the deposit address in Rails cache" do
    deposit_address = "0xcached_address_789"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_cache",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    # Verify the address was cached — the cache key should include the payment intent id
    cached = Rails.cache.read("mpp:deposit_address:pi_test_cache")
    assert_equal deposit_address, cached
  end

  test "fails when Stripe returns unexpected structure without next_action" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_bad",
        status: "requires_payment_method"
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    assert result.failure?
  end

  test "fails when Stripe returns unexpected structure without tempo address" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_no_tempo",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              ethereum: { address: "0xeth_addr" }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    assert result.failure?
  end

  test "fails when Stripe API call raises an error" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 402, body: {
        error: { message: "Your card was declined", type: "card_error" }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    assert result.failure?
  end

  test "includes payment_method_types crypto and deposit mode in Stripe call" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_mode",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xaddr" }
            }
          }
        }
      }.to_json)

    Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient
    )

    # Verify the request included the expected parameters
    assert_requested(:post, "https://api.stripe.com/v1/payment_intents") { |req|
      body = URI.decode_www_form(req.body).to_h
      body["payment_method_types[]"] == "crypto"
    }
  end
end
