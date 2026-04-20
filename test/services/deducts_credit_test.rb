# frozen_string_literal: true

require "test_helper"

class DeductsCreditTest < ActiveSupport::TestCase
  test "deducts one credit and logs transaction" do
    user = users(:credit_user)
    episode = episodes(:one)
    assert_equal 3, user.credits_remaining

    assert_difference -> { CreditTransaction.where(user: user, transaction_type: "usage").count }, 1 do
      result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 1)
      assert result.success?
    end

    assert_equal 2, user.reload.credits_remaining

    transaction = CreditTransaction.where(user: user, transaction_type: "usage").order(:created_at).last
    assert_equal(-1, transaction.amount)
    assert_equal 2, transaction.balance_after
  end

  test "returns failure when user has no credits" do
    user = users(:free_user)
    episode = episodes(:one)

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 1)

    assert result.failure?
    assert_equal "No credits available", result.message
  end

  test "returns failure when user has zero balance" do
    user = users(:jesse)
    episode = episodes(:one)
    assert_equal 0, user.credits_remaining

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 1)

    assert result.failure?
  end

  # --- Variable cost_in_credits ----------------------------------------------

  test "debits 2 credits when cost_in_credits is 2" do
    user = users(:credit_user)
    episode = episodes(:one)
    assert_equal 3, user.credits_remaining

    assert_difference -> { CreditTransaction.where(user: user, transaction_type: "usage").count }, 1 do
      result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 2)
      assert result.success?
    end

    assert_equal 1, user.reload.credits_remaining

    transaction = CreditTransaction.where(user: user, transaction_type: "usage").order(:created_at).last
    assert_equal(-2, transaction.amount)
    assert_equal 1, transaction.balance_after
  end

  test "debits 1 credit when cost_in_credits is 1" do
    user = users(:credit_user)
    episode = episodes(:one)
    assert_equal 3, user.credits_remaining

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 1)

    assert result.success?
    assert_equal 2, user.reload.credits_remaining

    transaction = CreditTransaction.where(user: user, transaction_type: "usage").order(:created_at).last
    assert_equal(-1, transaction.amount)
    assert_equal 2, transaction.balance_after
  end

  test "returns failure and writes no transaction when balance is less than cost_in_credits" do
    user = users(:credit_user)
    CreditBalance.for(user).update!(balance: 1)
    episode = episodes(:one)

    assert_no_difference -> { CreditTransaction.where(user: user, transaction_type: "usage").count } do
      result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 2)
      assert result.failure?
    end

    assert_equal 1, user.reload.credits_remaining
  end

  test "SendsCreditDepletedNudge fires when balance hits zero after a 2-credit debit" do
    user = users(:credit_user)
    CreditBalance.for(user).update!(balance: 2)
    episode = episodes(:one)

    Mocktail.replace(SendsCreditDepletedNudge)
    stubs { |m| SendsCreditDepletedNudge.call(user: m.any) }.with { Result.success }

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 2)

    assert result.success?
    assert_equal 0, user.reload.credits_remaining
    verify { SendsCreditDepletedNudge.call(user: user) }
  end

  test "sets :insufficient_credits code on failure when balance is short" do
    user = users(:credit_user)
    CreditBalance.for(user).update!(balance: 1)
    episode = episodes(:one)

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: 2)

    assert result.failure?
    assert_equal :insufficient_credits, result.code
  end
end
