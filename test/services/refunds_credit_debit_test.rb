# frozen_string_literal: true

require "test_helper"

# Tests for RefundsCreditDebit — the credit-path analogue to
# RefundsEpisodeUsage. When a credit user's episode fails after credits
# were debited via DeductsCredit, this service re-grants |amount| credits
# via GrantsCredits, tagged with a "refund_<credit_transaction_id>"
# session_id so the refund is idempotent if the failure callback fires
# twice.
class RefundsCreditDebitTest < ActiveSupport::TestCase
  setup do
    @credit_user = users(:credit_user)
    @podcast = podcasts(:one)
    CreditBalance.for(@credit_user).update!(balance: 3)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @credit_user,
      title: "Test",
      author: "Test",
      description: "Test",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :processing
    )
  end

  test "restores credit balance when credit user's episode failed after debit" do
    # Simulate the debit that would have happened during processing.
    DeductsCredit.call(user: @credit_user, episode: @episode, cost_in_credits: 1)
    assert_equal 2, @credit_user.reload.credits_remaining

    @episode.update!(status: :failed, error_message: "boom")

    RefundsCreditDebit.call(episode: @episode)

    assert_equal 3, @credit_user.reload.credits_remaining,
      "Refund should restore the debited credit"
  end

  test "restores full amount for 2-credit debit (premium voice / long article)" do
    DeductsCredit.call(user: @credit_user, episode: @episode, cost_in_credits: 2)
    assert_equal 1, @credit_user.reload.credits_remaining

    @episode.update!(status: :failed, error_message: "boom")

    RefundsCreditDebit.call(episode: @episode)

    assert_equal 3, @credit_user.reload.credits_remaining,
      "Refund should restore both debited credits"
  end

  test "creates a purchase-type CreditTransaction tagged refund_<id>" do
    DeductsCredit.call(user: @credit_user, episode: @episode, cost_in_credits: 1)
    usage_txn = CreditTransaction.where(
      user: @credit_user, episode: @episode, transaction_type: "usage"
    ).last
    assert_not_nil usage_txn

    assert_difference -> { CreditTransaction.count }, 1 do
      RefundsCreditDebit.call(episode: @episode)
    end

    refund_txn = CreditTransaction.where(user: @credit_user).order(:created_at).last
    assert_equal "purchase", refund_txn.transaction_type,
      "Refund should re-grant via GrantsCredits (purchase-type) — not a negative usage row"
    assert_equal 1, refund_txn.amount, "Refund amount should equal |usage amount|"
    assert_equal "refund_#{usage_txn.id}", refund_txn.stripe_session_id,
      "Refund must be tagged with refund_<usage_txn_id> for idempotency"
  end

  test "is idempotent — second call does not double-refund" do
    DeductsCredit.call(user: @credit_user, episode: @episode, cost_in_credits: 1)
    assert_equal 2, @credit_user.reload.credits_remaining

    RefundsCreditDebit.call(episode: @episode)
    assert_equal 3, @credit_user.reload.credits_remaining

    # Second call — simulates failure callback firing twice
    assert_no_difference -> { CreditTransaction.count } do
      RefundsCreditDebit.call(episode: @episode)
    end

    assert_equal 3, @credit_user.reload.credits_remaining,
      "Balance should not increase on second refund call"
  end

  test "no-ops when no usage CreditTransaction exists for the episode" do
    # Episode exists, user is a credit user, but nothing was debited.
    assert_equal 3, @credit_user.reload.credits_remaining

    assert_no_difference -> { CreditTransaction.count } do
      RefundsCreditDebit.call(episode: @episode)
    end

    assert_equal 3, @credit_user.reload.credits_remaining
  end

  test "ignores purchase-type transactions on the same user (only refunds usage rows)" do
    # A purchase transaction exists for this user with no episode, plus a
    # usage transaction for this episode. Only the usage row should be refunded.
    CreditTransaction.create!(
      user: @credit_user,
      amount: 5,
      balance_after: 8,
      transaction_type: "purchase",
      stripe_session_id: "cs_unrelated_purchase"
    )
    DeductsCredit.call(user: @credit_user, episode: @episode, cost_in_credits: 1)
    balance_before = @credit_user.reload.credits_remaining

    RefundsCreditDebit.call(episode: @episode)

    assert_equal balance_before + 1, @credit_user.reload.credits_remaining,
      "Only the usage-type row for this episode should be refunded"
  end
end
