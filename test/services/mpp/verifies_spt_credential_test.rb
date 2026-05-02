# frozen_string_literal: true

require "test_helper"

class Mpp::VerifiesSptCredentialTest < ActiveSupport::TestCase
  setup do
    @amount_cents = AppConfig::Mpp::PRICE_STANDARD_CENTS
    @currency = AppConfig::Mpp::CURRENCY
    @spt = "spt_test_#{SecureRandom.hex(8)}"
    @stripe_pi_id = "pi_test_#{SecureRandom.hex(8)}"
    Stripe.api_key = "sk_test_fake"

    challenge_result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: :standard,
      method: :stripe
    )
    @challenge_data = challenge_result.data

    @challenge = {
      "id" => @challenge_data[:id],
      "realm" => @challenge_data[:realm],
      "method" => @challenge_data[:method],
      "intent" => @challenge_data[:intent],
      "request" => @challenge_data[:request],
      "expires" => @challenge_data[:expires]
    }

    @payload = { "spt" => @spt }

    @mpp_payment = MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: @challenge["id"],
      status: :pending
    )
  end

  test "returns failure when spt is missing from payload" do
    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: {},
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_match(/Missing spt/, result.error)
  end

  test "returns failure when spt is empty string" do
    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: { "spt" => "" },
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_match(/Missing spt/, result.error)
  end

  test "returns success with stripe_payment_intent_id when PaymentIntent succeeds" do
    stub_spt_success(payment_intent_id: @stripe_pi_id)

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.success?, "expected success, got: #{result.error.inspect}"
    assert_equal @stripe_pi_id, result.data[:tx_hash]
    assert_equal @stripe_pi_id, result.data[:stripe_payment_intent_id]
    assert_equal @challenge["id"], result.data[:challenge_id]
    assert_equal :standard, result.data[:voice_tier]
  end

  test "calls Stripe with shared_payment_granted_token and the mppx-convention idempotency_key" do
    expected_key = "mppx_#{@challenge["id"]}_#{@spt}"
    stub = stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .with do |req|
        req.body.include?("shared_payment_granted_token") &&
          req.body.include?(@spt) &&
          req.headers["Idempotency-Key"] == expected_key &&
          req.headers["Stripe-Version"] == AppConfig::Mpp::STRIPE_API_VERSION
      end
      .to_return(
        status: 200,
        body: {
          id: @stripe_pi_id,
          object: "payment_intent",
          amount: @amount_cents,
          currency: @currency,
          status: "succeeded"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert_requested(stub, times: 1)
  end

  test "uses preview Stripe API version" do
    stub_spt_success(payment_intent_id: @stripe_pi_id)

    Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert_requested(:post, "https://api.stripe.com/v1/payment_intents") do |req|
      req.headers["Stripe-Version"] == AppConfig::Mpp::STRIPE_API_VERSION
    end
  end

  test "returns failure with code :replay when Stripe returns idempotent-replayed: true" do
    stub_spt_replay(payment_intent_id: @stripe_pi_id)

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_equal :replay, result.code
  end

  test "returns failure with code :requires_action when PaymentIntent status is requires_action" do
    stub_spt_status(payment_intent_id: @stripe_pi_id, status: "requires_action")

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_equal :requires_action, result.code
  end

  test "returns failure for any other PaymentIntent status" do
    stub_spt_status(payment_intent_id: @stripe_pi_id, status: "processing")

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_match(/processing/, result.error)
  end

  test "classifies card_declined as permanent (code :card_declined)" do
    stub_card_error(decline_code: "card_declined")

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_equal :card_declined, result.code
  end

  test "classifies try_again_later as transient (code :transient)" do
    stub_card_error(decline_code: "try_again_later")

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_equal :transient, result.code
  end

  test "classifies processing_error as transient (code :transient)" do
    stub_card_error(decline_code: "processing_error")

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_equal :transient, result.code
  end

  test "classifies generic Stripe error (no decline_code) as permanent stripe_error" do
    stub_generic_stripe_error

    result = Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert result.failure?
    assert_equal :stripe_error, result.code
  end

  test "extracts amount and currency from the HMAC-signed challenge request blob" do
    stub = stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .with do |req|
        req.body.include?("amount=#{@amount_cents}") &&
          req.body.include?("currency=#{@currency}")
      end
      .to_return(
        status: 200,
        body: {
          id: @stripe_pi_id,
          object: "payment_intent",
          amount: @amount_cents,
          currency: @currency,
          status: "succeeded"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    Mpp::VerifiesSptCredential.call(
      challenge: @challenge,
      payload: @payload,
      mpp_payment: @mpp_payment
    )

    assert_requested(stub, times: 1)
  end

  private

  def stub_spt_success(payment_intent_id:)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(
        status: 200,
        body: {
          id: payment_intent_id,
          object: "payment_intent",
          amount: @amount_cents,
          currency: @currency,
          status: "succeeded"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_spt_replay(payment_intent_id:)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(
        status: 200,
        body: {
          id: payment_intent_id,
          object: "payment_intent",
          amount: @amount_cents,
          currency: @currency,
          status: "succeeded"
        }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "idempotent-replayed" => "true"
        }
      )
  end

  def stub_spt_status(payment_intent_id:, status:)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(
        status: 200,
        body: {
          id: payment_intent_id,
          object: "payment_intent",
          amount: @amount_cents,
          currency: @currency,
          status: status
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_card_error(decline_code:)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(
        status: 402,
        body: {
          error: {
            type: "card_error",
            code: "card_declined",
            decline_code: decline_code,
            message: "Your card was declined."
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_generic_stripe_error
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(
        status: 500,
        body: {
          error: {
            type: "api_error",
            message: "Internal server error"
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
