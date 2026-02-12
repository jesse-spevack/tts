# frozen_string_literal: true

require "test_helper"

class DeductsCreditTest < ActiveSupport::TestCase
  test "deducts one credit and logs transaction" do
    user = users(:credit_user)
    episode = episodes(:one)
    assert_equal 3, user.credits_remaining

    assert_difference -> { CreditTransaction.where(user: user, transaction_type: "usage").count }, 1 do
      result = DeductsCredit.call(user: user, episode: episode)
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

    result = DeductsCredit.call(user: user, episode: episode)

    assert result.failure?
    assert_equal "No credits available", result.message
  end

  test "returns failure when user has zero balance" do
    user = users(:jesse)
    episode = episodes(:one)
    assert_equal 0, user.credits_remaining

    result = DeductsCredit.call(user: user, episode: episode)

    assert result.failure?
  end
end
