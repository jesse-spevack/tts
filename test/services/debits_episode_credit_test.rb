# frozen_string_literal: true

require "test_helper"

class DebitsEpisodeCreditTest < ActiveSupport::TestCase
  # All fixture episodes are URL-typed, so build a paste episode for tests
  # that exercise the delegate-to-DeductsCredit path. Using update_columns to
  # bypass validations (no real source_text needed for the debit logic).
  def build_paste_episode(user)
    episode = episodes(:one).dup
    episode.user = user
    episode.source_type = :paste
    episode.source_url = nil
    episode.save(validate: false)
    episode
  end

  def url_episode_for(user)
    episode = episodes(:one).dup
    episode.user = user
    episode.source_type = :url
    episode.source_url = "https://example.com/article"
    episode.save(validate: false)
    episode
  end

  # --- Bypass rules ---------------------------------------------------------

  test "returns skipped/:complimentary for complimentary user" do
    user = users(:complimentary_user)
    episode = build_paste_episode(user)

    assert_no_difference -> { CreditTransaction.where(user: user).count } do
      result = DebitsEpisodeCredit.call(user: user, episode: episode, cost_in_credits: 2)

      assert result.success?
      assert_equal :skipped, result.data[:status]
      assert_equal :complimentary, result.data[:reason]
    end
  end

  test "returns skipped/:unlimited for unlimited user" do
    user = users(:unlimited_user)
    episode = build_paste_episode(user)

    assert_no_difference -> { CreditTransaction.where(user: user).count } do
      result = DebitsEpisodeCredit.call(user: user, episode: episode, cost_in_credits: 2)

      assert result.success?
      assert_equal :skipped, result.data[:status]
      assert_equal :unlimited, result.data[:reason]
    end
  end

  test "returns skipped/:url_deferred for url episode" do
    user = users(:credit_user)
    episode = url_episode_for(user)

    assert_no_difference -> { CreditTransaction.where(user: user).count } do
      result = DebitsEpisodeCredit.call(user: user, episode: episode, cost_in_credits: 1)

      assert result.success?
      assert_equal :skipped, result.data[:status]
      assert_equal :url_deferred, result.data[:reason]
    end
  end

  # --- Delegation -----------------------------------------------------------

  test "delegates to DeductsCredit for credit user with balance, balance decreases" do
    user = users(:credit_user)
    episode = build_paste_episode(user)
    assert_equal 3, user.credits_remaining

    result = DebitsEpisodeCredit.call(user: user, episode: episode, cost_in_credits: 2)

    assert result.success?
    assert_equal :debited, result.data[:status]
    assert_kind_of CreditBalance, result.data[:balance]
    assert_equal 1, user.reload.credits_remaining

    txn = CreditTransaction.where(user: user, transaction_type: "usage").order(:created_at).last
    assert_equal(-2, txn.amount)
    assert_equal 1, txn.balance_after
  end

  test "propagates Result.failure from DeductsCredit when balance is insufficient" do
    user = users(:credit_user)
    CreditBalance.for(user).update!(balance: 1)
    episode = build_paste_episode(user)

    assert_no_difference -> { CreditTransaction.where(user: user, transaction_type: "usage").count } do
      result = DebitsEpisodeCredit.call(user: user, episode: episode, cost_in_credits: 2)

      assert result.failure?
      assert_equal :insufficient_credits, result.code
    end

    assert_equal 1, user.reload.credits_remaining
  end

  # Bypass rules take precedence over balance — a complimentary/unlimited
  # user with zero balance should still succeed (skipped), not fail.
  test "complimentary user with zero balance still skipped, not failed" do
    user = users(:complimentary_user)
    CreditBalance.for(user).update!(balance: 0)
    episode = build_paste_episode(user)

    result = DebitsEpisodeCredit.call(user: user, episode: episode, cost_in_credits: 2)

    assert result.success?
    assert_equal :skipped, result.data[:status]
  end
end
