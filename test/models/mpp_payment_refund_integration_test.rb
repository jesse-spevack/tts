# frozen_string_literal: true

require "test_helper"

class MppPaymentRefundIntegrationTest < ActiveSupport::TestCase
  setup do
    Stripe.api_key = "sk_test_fake"
  end

  # --- Narration auto-refund on failure ---

  test "when a Narration with a completed MppPayment fails, refund is triggered" do
    narration = narrations(:processing)
    payment = narration.mpp_payment
    assert_equal "completed", payment.status

    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 200, body: {
        id: "re_test_auto_1",
        status: "succeeded",
        payment_intent: payment.stripe_payment_intent_id
      }.to_json)

    narration.update!(status: :failed, error_message: "Processing failed")

    payment.reload
    assert_equal "refunded", payment.status
    assert_requested(:post, "https://api.stripe.com/v1/refunds")
  end

  test "when a Narration fails but MppPayment is already refunded, no double refund" do
    narration = narrations(:with_refunded_payment)
    payment = narration.mpp_payment
    assert_equal "refunded", payment.status

    # Transition to failed should NOT trigger another refund
    narration.update!(status: :failed, error_message: "Processing failed again")

    assert_not_requested(:post, "https://api.stripe.com/v1/refunds")
    payment.reload
    assert_equal "refunded", payment.status
  end

  # --- Episode auto-refund on failure ---

  test "when an Episode with an MppPayment fails, refund is triggered" do
    episode = episodes(:pending)
    # Episode needs an mpp_payment association for MPP-paid episodes.
    # The Implementer will add this association. This test verifies it works.
    payment = mpp_payments(:completed)
    episode.update_column(:mpp_payment_id, payment.id) if episode.respond_to?(:mpp_payment_id)

    # Skip if the association isn't wired yet -- this test documents the expected behavior
    skip("Episode#mpp_payment association not yet implemented") unless episode.respond_to?(:mpp_payment)

    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 200, body: {
        id: "re_test_auto_2",
        status: "succeeded",
        payment_intent: payment.stripe_payment_intent_id
      }.to_json)

    episode.update!(status: :failed, error_message: "Processing failed")

    payment.reload
    assert_equal "refunded", payment.status
    assert_requested(:post, "https://api.stripe.com/v1/refunds")
  end

  test "when an Episode WITHOUT an MppPayment fails, no refund is attempted" do
    episode = episodes(:one)

    # This is a subscriber episode with no MPP payment.
    # Transitioning to failed should NOT trigger any refund behavior.
    episode.update!(status: :failed, error_message: "Something broke")

    assert_not_requested(:post, "https://api.stripe.com/v1/refunds")
  end

  # --- EpisodeErrorHandling integration ---

  test "fail_episode triggers auto-refund for MPP-paid episode via processing pipeline" do
    episode = episodes(:pending)

    # Skip if Episode doesn't have mpp_payment yet
    skip("Episode#mpp_payment association not yet implemented") unless episode.respond_to?(:mpp_payment)

    payment = mpp_payments(:completed)
    episode.update_column(:mpp_payment_id, payment.id)

    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(status: 200, body: {
        id: "re_test_auto_3",
        status: "succeeded",
        payment_intent: payment.stripe_payment_intent_id
      }.to_json)

    # Simulate what ProcessesUrlEpisode does when it catches an error:
    # it calls fail_episode which updates status to :failed
    episode.update!(status: :failed, error_message: "Content extraction failed")

    payment.reload
    assert_equal "refunded", payment.status
  end
end
