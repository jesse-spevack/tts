# frozen_string_literal: true

require "test_helper"

class CleanupStaleMppPaymentsJobTest < ActiveSupport::TestCase
  setup do
    Stripe.api_key = "sk_test_fake"

    @stale_pending = MppPayment.create!(
      amount_cents: 100,
      currency: "usd",
      challenge_id: "ch_stale_#{SecureRandom.hex(6)}",
      deposit_address: "0xstale123",
      stripe_payment_intent_id: "pi_stale_123",
      status: :pending
    )
    @stale_pending.update_column(:created_at, (AppConfig::Mpp::CHALLENGE_TTL_SECONDS + 60).seconds.ago)

    @recent_pending = MppPayment.create!(
      amount_cents: 100,
      currency: "usd",
      challenge_id: "ch_recent_#{SecureRandom.hex(6)}",
      deposit_address: "0xrecent456",
      stripe_payment_intent_id: "pi_recent_456",
      status: :pending
    )
  end

  test "cancels Stripe PaymentIntent for stale pending payments" do
    cancel_stub = stub_stripe_cancel(@stale_pending.stripe_payment_intent_id)

    CleanupStaleMppPaymentsJob.perform_now

    assert_requested cancel_stub
  end

  test "updates stale pending payments to failed status" do
    stub_stripe_cancel(@stale_pending.stripe_payment_intent_id)

    CleanupStaleMppPaymentsJob.perform_now

    @stale_pending.reload
    assert_equal "failed", @stale_pending.status
  end

  test "does not touch recent pending payments within TTL" do
    stub_stripe_cancel(@stale_pending.stripe_payment_intent_id)

    CleanupStaleMppPaymentsJob.perform_now

    @recent_pending.reload
    assert_equal "pending", @recent_pending.status
  end

  test "does not touch completed payments" do
    completed = mpp_payments(:completed)

    stub_stripe_cancel(@stale_pending.stripe_payment_intent_id)

    CleanupStaleMppPaymentsJob.perform_now

    completed.reload
    assert_equal "completed", completed.status
  end

  test "does not touch refunded payments" do
    refunded = mpp_payments(:refunded)

    stub_stripe_cancel(@stale_pending.stripe_payment_intent_id)

    CleanupStaleMppPaymentsJob.perform_now

    refunded.reload
    assert_equal "refunded", refunded.status
  end

  test "handles Stripe API errors gracefully and continues" do
    second_stale = MppPayment.create!(
      amount_cents: 100,
      currency: "usd",
      challenge_id: "ch_stale2_#{SecureRandom.hex(6)}",
      deposit_address: "0xstale789",
      stripe_payment_intent_id: "pi_stale_789",
      status: :pending
    )
    second_stale.update_column(:created_at, (AppConfig::Mpp::CHALLENGE_TTL_SECONDS + 120).seconds.ago)

    # First call raises, second succeeds
    stub_stripe_cancel_error(@stale_pending.stripe_payment_intent_id)
    stub_stripe_cancel(second_stale.stripe_payment_intent_id)

    # Should not raise
    CleanupStaleMppPaymentsJob.perform_now

    # The one that errored should still be marked failed
    @stale_pending.reload
    assert_equal "failed", @stale_pending.status

    # The second one should also be marked failed
    second_stale.reload
    assert_equal "failed", second_stale.status
  end

  test "skips Stripe cancellation when no stripe_payment_intent_id" do
    no_pi = MppPayment.create!(
      amount_cents: 100,
      currency: "usd",
      challenge_id: "ch_nopi_#{SecureRandom.hex(6)}",
      deposit_address: "0xnopi",
      stripe_payment_intent_id: nil,
      status: :pending
    )
    no_pi.update_column(:created_at, (AppConfig::Mpp::CHALLENGE_TTL_SECONDS + 60).seconds.ago)

    stub_stripe_cancel(@stale_pending.stripe_payment_intent_id)

    CleanupStaleMppPaymentsJob.perform_now

    no_pi.reload
    assert_equal "failed", no_pi.status
  end

  private

  def stub_stripe_cancel(payment_intent_id)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents/#{payment_intent_id}/cancel")
      .to_return(
        status: 200,
        body: { id: payment_intent_id, status: "canceled" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_stripe_cancel_error(payment_intent_id)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents/#{payment_intent_id}/cancel")
      .to_return(
        status: 400,
        body: {
          error: {
            type: "invalid_request_error",
            message: "This PaymentIntent's status is canceled."
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
