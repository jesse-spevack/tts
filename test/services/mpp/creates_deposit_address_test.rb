# frozen_string_literal: true

require "test_helper"

class Mpp::CreatesDepositAddressTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 100
    @currency = "usd"
    @challenge_id = "ch_#{SecureRandom.hex(16)}"
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
      challenge_id: @challenge_id
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
      challenge_id: @challenge_id
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
      challenge_id: @challenge_id
    )

    assert_equal "pi_test_456", result.data[:payment_intent_id]
  end

  test "caches the payment_intent_id keyed by deposit_address" do
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
      challenge_id: @challenge_id
    )

    # Cache is keyed by deposit_address (the value the client echoes back)
    # and stores the payment_intent_id for later Stripe linkage.
    cached = Rails.cache.read("mpp:deposit_address:#{deposit_address}")
    assert_equal "pi_test_cache", cached
  end

  test "persists a pending MppPayment row linked to challenge_id and payment_intent_id" do
    deposit_address = "0xpersist_addr_abc"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_persist",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    assert_difference "MppPayment.count", 1 do
      Mpp::CreatesDepositAddress.call(
        amount_cents: @amount_cents,
        currency: @currency,
        challenge_id: @challenge_id
      )
    end

    payment = MppPayment.find_by!(challenge_id: @challenge_id)
    assert_equal "pending", payment.status
    assert_equal "pi_test_persist", payment.stripe_payment_intent_id
    assert_equal deposit_address, payment.deposit_address
    assert_equal @amount_cents, payment.amount_cents
    assert_equal @currency, payment.currency
  end

  test "does not persist MppPayment when Stripe response is missing deposit address" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_no_addr",
        status: "requires_payment_method"
      }.to_json)

    assert_no_difference "MppPayment.count" do
      result = Mpp::CreatesDepositAddress.call(
        amount_cents: @amount_cents,
        currency: @currency,
        challenge_id: @challenge_id
      )
      assert result.failure?
    end
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
      challenge_id: @challenge_id
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
      challenge_id: @challenge_id
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
      challenge_id: @challenge_id
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
      challenge_id: @challenge_id
    )

    # Verify the request included the expected parameters
    assert_requested(:post, "https://api.stripe.com/v1/payment_intents") { |req|
      body = URI.decode_www_form(req.body).to_h
      body["payment_method_types[]"] == "crypto"
    }
  end
end
