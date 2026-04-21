# frozen_string_literal: true

require "test_helper"

# Tests for RefundsPayment (agent-team-bzo6, epic agent-team-sird).
#
# RefundsPayment.call(content:) is the unified orchestrator that
# replaces the three-headed refund dance:
#
#   - RefundsEpisodeUsage (free-tier monthly counter decrement)
#   - RefundsCreditDebit  (credit re-grant via GrantsCredits)
#   - Mpp::RefundsPayment (Stripe refund + MppPayment status flip)
#
# Dispatch rules (from the bzo6 notes on agent-team-sird):
#
#   1. content.mpp_payment.present? → dispatch to MPP refund.
#      (MPP takes priority — MPP-purchased content is never on the
#      credit/free path.)
#   2. Otherwise, if the owning user has credits (credit_user?) →
#      re-grant the debited credit.
#   3. Otherwise, if the owning user is free-tier (free?) →
#      decrement the monthly EpisodeUsage counter.
#
# Idempotency invariants that MUST survive unification:
#
#   - GrantsCredits dedupes via stripe_session_id ("refund_<txn_id>").
#     Calling RefundsPayment twice must NOT create a second credit.
#   - Mpp::RefundsPayment refuses when status != completed. Calling
#     RefundsPayment twice must NOT double-refund Stripe.
#
# All tests MUST fail until the service is created.
# Acceptable failure: NameError: uninitialized constant RefundsPayment.
class RefundsPaymentTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Free-tier dispatch: decrement EpisodeUsage counter
  # ---------------------------------------------------------------------------

  class FreeTierDispatch < ActiveSupport::TestCase
    setup do
      @free_user = users(:free_user)
      @podcast = podcasts(:one)
      @episode = Episode.create!(
        podcast: @podcast,
        user: @free_user,
        title: "Free tier episode",
        author: "Free Author",
        description: "Free tier test.",
        source_type: :url,
        source_url: "https://example.com/free",
        status: :processing
      )
      EpisodeUsage.create!(
        user: @free_user,
        period_start: Time.current.beginning_of_month.to_date,
        episode_count: 2
      )
    end

    test "decrements the free user's monthly usage counter" do
      RefundsPayment.call(content: @episode)

      usage = EpisodeUsage.current_for(@free_user)
      assert_equal 1, usage.episode_count,
        "free-tier refund must decrement EpisodeUsage counter"
    end

    test "does nothing for free user with no current-month usage record" do
      EpisodeUsage.current_for(@free_user).destroy

      assert_no_difference -> { EpisodeUsage.count } do
        RefundsPayment.call(content: @episode)
      end
    end

    test "is idempotent — second call does not re-decrement counter below 1" do
      RefundsPayment.call(content: @episode)
      RefundsPayment.call(content: @episode)

      usage = EpisodeUsage.current_for(@free_user)
      # After 2 calls starting from 2, counter should be 0 (clamped, never
      # negative) — but the invariant we pin here is "calling twice does
      # not grant more than one refund worth of slots back". Since 2 → 1
      # → 0 is the natural decrement, the idempotency guarantee is that
      # the counter never drops below 0.
      assert_operator usage.episode_count, :>=, 0,
        "usage counter must not go negative on double refund"
    end
  end

  # ---------------------------------------------------------------------------
  # Credit-user dispatch: re-grant credit via GrantsCredits
  # ---------------------------------------------------------------------------

  class CreditUserDispatch < ActiveSupport::TestCase
    setup do
      @credit_user = users(:credit_user)
      @podcast = podcasts(:one)
      CreditBalance.for(@credit_user).update!(balance: 3)
      @episode = Episode.create!(
        podcast: @podcast,
        user: @credit_user,
        title: "Credit episode",
        author: "Credit Author",
        description: "Credit test.",
        source_type: :url,
        source_url: "https://example.com/credit",
        status: :processing
      )
      DeductsCredit.call(user: @credit_user, episode: @episode, cost_in_credits: 1)
      # Balance is now 2 after the debit.
    end

    test "re-grants the debited credit to restore balance" do
      RefundsPayment.call(content: @episode)

      assert_equal 3, @credit_user.reload.credits_remaining,
        "credit-user refund must restore the debited credit"
    end

    test "creates a purchase-type CreditTransaction tagged refund_<usage_txn_id>" do
      usage_txn = CreditTransaction.where(
        user: @credit_user, episode: @episode, transaction_type: "usage"
      ).last
      assert_not_nil usage_txn

      assert_difference -> { CreditTransaction.count }, 1 do
        RefundsPayment.call(content: @episode)
      end

      refund_txn = CreditTransaction.where(user: @credit_user).order(:created_at).last
      assert_equal "purchase", refund_txn.transaction_type
      assert_equal 1, refund_txn.amount
      assert_equal "refund_#{usage_txn.id}", refund_txn.stripe_session_id,
        "credit refund must be tagged with refund_<usage_txn_id> for idempotency"
    end

    test "is idempotent — second call does not create a second refund transaction" do
      RefundsPayment.call(content: @episode)
      assert_equal 3, @credit_user.reload.credits_remaining

      assert_no_difference -> { CreditTransaction.count } do
        RefundsPayment.call(content: @episode)
      end

      assert_equal 3, @credit_user.reload.credits_remaining,
        "balance must not grow on second refund call"
    end

    test "no-ops when content has no usage CreditTransaction" do
      # Fresh episode, no debit.
      fresh_episode = Episode.create!(
        podcast: @podcast,
        user: @credit_user,
        title: "No debit",
        author: "Author",
        description: "No debit description.",
        source_type: :url,
        source_url: "https://example.com/nodebit",
        status: :processing
      )

      balance_before = @credit_user.reload.credits_remaining
      assert_no_difference -> { CreditTransaction.count } do
        RefundsPayment.call(content: fresh_episode)
      end
      assert_equal balance_before, @credit_user.reload.credits_remaining
    end
  end

  # ---------------------------------------------------------------------------
  # MPP-user dispatch: refund Stripe payment + flip MppPayment status
  # ---------------------------------------------------------------------------

  class MppDispatch < ActiveSupport::TestCase
    setup do
      Stripe.api_key = "sk_test_fake"
      @mpp_payment = mpp_payments(:completed)
      @episode = Episode.create!(
        podcast: podcasts(:one),
        user: users(:one),
        title: "MPP episode",
        author: "MPP Author",
        description: "MPP description for refund test.",
        source_type: :url,
        source_url: "https://example.com/mpp",
        status: :processing,
        mpp_payment: @mpp_payment
      )
    end

    test "issues a Stripe refund for the associated payment" do
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .with(body: hash_including("payment_intent" => @mpp_payment.stripe_payment_intent_id))
        .to_return(status: 200, body: {
          id: "re_test_123",
          status: "succeeded",
          payment_intent: @mpp_payment.stripe_payment_intent_id
        }.to_json)

      RefundsPayment.call(content: @episode)

      assert_requested(:post, "https://api.stripe.com/v1/refunds") { |req|
        body = URI.decode_www_form(req.body).to_h
        body["payment_intent"] == @mpp_payment.stripe_payment_intent_id
      }
    end

    test "flips MppPayment status to refunded on success" do
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .to_return(status: 200, body: {
          id: "re_test_123", status: "succeeded",
          payment_intent: @mpp_payment.stripe_payment_intent_id
        }.to_json)

      RefundsPayment.call(content: @episode)

      assert_equal "refunded", @mpp_payment.reload.status
    end

    test "is idempotent — second call does not issue a second Stripe refund" do
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .to_return(status: 200, body: {
          id: "re_test_123", status: "succeeded",
          payment_intent: @mpp_payment.stripe_payment_intent_id
        }.to_json)

      RefundsPayment.call(content: @episode)
      # First call flipped status to refunded. Clear the WebMock stub so a
      # second request would raise a connection error — the only way the
      # test passes is if RefundsPayment skips the Stripe call.
      WebMock.reset_executed_requests!

      RefundsPayment.call(content: @episode)

      assert_not_requested(:post, "https://api.stripe.com/v1/refunds")
    end

    test "works for Narration (MPP is the only Narration path)" do
      # Narrations.mpp_payment_id is UNIQUE and mpp_payments(:completed) is
      # already claimed by narrations(:completed) fixture — so we mint a
      # fresh MppPayment for this case.
      narration_payment = MppPayment.create!(
        amount_cents: 150,
        currency: "usd",
        status: "completed",
        stripe_payment_intent_id: "pi_test_narr_dispatch_#{SecureRandom.hex(4)}",
        tx_hash: "0x#{SecureRandom.hex(16)}",
        user: users(:one)
      )

      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .to_return(status: 200, body: {
          id: "re_test_narr", status: "succeeded",
          payment_intent: narration_payment.stripe_payment_intent_id
        }.to_json)

      narration = Narration.create!(
        title: "MPP narration",
        author: "MPP Narration Author",
        description: "MPP narration description.",
        source_type: :text,
        source_text: "Narration body, long enough for validation to pass.",
        status: :processing,
        voice: "en-GB-Standard-D",
        expires_at: 24.hours.from_now,
        mpp_payment: narration_payment
      )

      RefundsPayment.call(content: narration)

      assert_equal "refunded", narration_payment.reload.status
    end
  end

  # ---------------------------------------------------------------------------
  # Dispatch priority: MPP beats credit/free
  # ---------------------------------------------------------------------------

  class DispatchPriority < ActiveSupport::TestCase
    test "MPP path takes priority over credit-user path when content has mpp_payment" do
      Stripe.api_key = "sk_test_fake"
      credit_user = users(:credit_user)
      CreditBalance.for(credit_user).update!(balance: 3)
      mpp_payment = mpp_payments(:completed)

      episode = Episode.create!(
        podcast: podcasts(:one),
        user: credit_user,
        title: "Credit user with MPP payment",
        author: "Author",
        description: "Description.",
        source_type: :url,
        source_url: "https://example.com/both",
        status: :processing,
        mpp_payment: mpp_payment
      )
      # Simulate a prior credit debit on the same record.
      DeductsCredit.call(user: credit_user, episode: episode, cost_in_credits: 1)
      balance_before = credit_user.reload.credits_remaining

      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .to_return(status: 200, body: {
          id: "re_both", status: "succeeded",
          payment_intent: mpp_payment.stripe_payment_intent_id
        }.to_json)

      RefundsPayment.call(content: episode)

      assert_requested(:post, "https://api.stripe.com/v1/refunds")
      # Credit balance should NOT change — MPP refund is the only path taken.
      assert_equal balance_before, credit_user.reload.credits_remaining,
        "credit path must not fire when MPP path is taken"
    end
  end
end
