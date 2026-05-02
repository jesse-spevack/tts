# frozen_string_literal: true

require "test_helper"

class Mpp::RefundsPaymentTest < ActiveSupport::TestCase
  setup do
    @completed_payment = mpp_payments(:completed)
    Stripe.api_key = "sk_test_fake"
  end

  # --- Happy path ---

  test "calls Stripe::Refund.create with correct payment_intent_id" do
    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .with(body: hash_including("payment_intent" => @completed_payment.stripe_payment_intent_id))
      .to_return(status: 200, body: {
        id: "re_test_123",
        status: "succeeded",
        payment_intent: @completed_payment.stripe_payment_intent_id
      }.to_json)

    Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    assert_requested(:post, "https://api.stripe.com/v1/refunds") { |req|
      body = URI.decode_www_form(req.body).to_h
      body["payment_intent"] == @completed_payment.stripe_payment_intent_id
    }
  end

  test "updates MppPayment status to refunded" do
    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 200, body: {
        id: "re_test_123",
        status: "succeeded",
        payment_intent: @completed_payment.stripe_payment_intent_id
      }.to_json)

    Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    @completed_payment.reload
    assert_equal "refunded", @completed_payment.status
  end

  test "returns Result.success on happy path" do
    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 200, body: {
        id: "re_test_123",
        status: "succeeded",
        payment_intent: @completed_payment.stripe_payment_intent_id
      }.to_json)

    result = Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    assert result.success?
  end

  # --- Guard cases ---

  test "returns failure if MppPayment status is pending" do
    pending_payment = mpp_payments(:one)
    assert_equal "pending", pending_payment.status

    result = Mpp::RefundsPayment.call(mpp_payment: pending_payment)

    assert result.failure?
    assert_no_requested_stripe_refund
  end

  test "returns failure if MppPayment status is already refunded (idempotency)" do
    refunded_payment = mpp_payments(:refunded)
    assert_equal "refunded", refunded_payment.status

    result = Mpp::RefundsPayment.call(mpp_payment: refunded_payment)

    assert result.failure?
    assert_no_requested_stripe_refund
  end

  test "returns failure if stripe_payment_intent_id is blank" do
    @completed_payment.update_column(:stripe_payment_intent_id, nil)

    result = Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    assert result.failure?
    assert_no_requested_stripe_refund
  end

  test "handles Stripe API errors gracefully and returns failure" do
    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 400, body: {
        error: {
          type: "invalid_request_error",
          message: "Charge ch_xxx has already been refunded."
        }
      }.to_json)

    result = Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    assert result.failure?
    # Payment status should NOT change to refunded on Stripe error
    @completed_payment.reload
    assert_equal "completed", @completed_payment.status
  end

  # --- Stranded-money protection ---
  # These cases prove that a Stripe failure never silently leaves an
  # mpp_payment in status=completed with no trace of the failure.

  test "flags payment for review when Stripe reports no successful charge to refund" do
    error_message = "This PaymentIntent (pi_test) does not have a successful charge to refund."
    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 400, body: {
        error: {
          type: "invalid_request_error",
          message: error_message
        }
      }.to_json)

    result = Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    assert result.failure?
    @completed_payment.reload
    assert_equal "completed", @completed_payment.status
    assert @completed_payment.needs_review, "expected needs_review to be true after refund failure"
    assert_includes @completed_payment.refund_error, "does not have a successful charge to refund"
  end

  test "flags payment for review on unknown Stripe error" do
    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 500, body: {
        error: {
          type: "api_error",
          message: "Something went wrong on Stripe's end."
        }
      }.to_json)

    result = Mpp::RefundsPayment.call(mpp_payment: @completed_payment)

    assert result.failure?
    @completed_payment.reload
    assert_equal "completed", @completed_payment.status
    assert @completed_payment.needs_review, "expected needs_review to be true after generic Stripe error"
    assert @completed_payment.refund_error.present?, "expected refund_error to be recorded"
  end

  # --- SPT refund integration (agent-team-k71e.6) ---
  #
  # When the SPT path was added (k71e.4 + k71e.5), the redemption PI id
  # ended up in mpp_payment.tx_hash but never in stripe_payment_intent_id.
  # That broke refunds for every SPT-paid row: the guard at
  # refunds_payment.rb:17 bails on `stripe_payment_intent_id.blank?`.
  #
  # This test reproduces the bug end-to-end against the REAL finalizer
  # (no Mocktail of FinalizesNarration / FinalizesEpisode — see bead
  # constraints). On main it goes red because RefundsPayment never
  # reaches Stripe::Refund.create.

  test "SPT-paid row produced via the real finalizer can be refunded via Stripe" do
    spt_pi_id = "pi_spt_refund_test_#{SecureRandom.hex(8)}"

    # Mimic Mpp::ProvisionsChallenge's stripe-method row: pending,
    # no deposit_address, no stripe_payment_intent_id. After the SPT
    # is redeemed, Mpp::FinalizesNarration runs with tx_hash set to
    # the SPT-redemption PI id.
    mpp_payment = MppPayment.create!(
      amount_cents: 150,
      currency: "usd",
      challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: nil,
      stripe_payment_intent_id: nil,
      status: :pending
    )

    finalize_result = Mpp::FinalizesNarration.call(
      mpp_payment: mpp_payment,
      tx_hash: spt_pi_id,
      params: { source_type: "text", text: "x" * 50, title: "T", voice: "felix" }
    )
    assert finalize_result.success?, "Setup precondition: finalizer must succeed"
    mpp_payment.reload
    assert_equal "completed", mpp_payment.status, "Setup precondition: row is completed"

    refund_stub = stub_request(:post, "https://api.stripe.com/v1/refunds")
      .with(body: hash_including("payment_intent" => spt_pi_id))
      .to_return(status: 200, body: {
        id: "re_test_spt_123",
        status: "succeeded",
        payment_intent: spt_pi_id
      }.to_json)

    result = Mpp::RefundsPayment.call(mpp_payment: mpp_payment)

    assert result.success?,
      "SPT-paid row must refund successfully — currently fails because " \
      "FinalizesNarration drops the SPT PI id and RefundsPayment bails " \
      "on stripe_payment_intent_id.blank?"
    assert_requested(refund_stub, at_least_times: 1)
    mpp_payment.reload
    assert_equal "refunded", mpp_payment.status
  end

  private

  def assert_no_requested_stripe_refund
    assert_not_requested(:post, "https://api.stripe.com/v1/refunds")
  end
end
