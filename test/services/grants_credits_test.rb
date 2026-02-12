# frozen_string_literal: true

require "test_helper"

class GrantsCreditsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "creates credit balance and grants credits" do
    result = GrantsCredits.call(
      user: @user,
      amount: 5,
      stripe_session_id: "cs_test_new"
    )

    assert result.success?
    assert_equal 5, @user.credit_balance.reload.balance
  end

  test "creates credit transaction with purchase type" do
    assert_difference "CreditTransaction.count", 1 do
      GrantsCredits.call(
        user: @user,
        amount: 5,
        stripe_session_id: "cs_test_txn"
      )
    end

    txn = CreditTransaction.last
    assert_equal @user, txn.user
    assert_equal 5, txn.amount
    assert_equal 5, txn.balance_after
    assert_equal "purchase", txn.transaction_type
    assert_equal "cs_test_txn", txn.stripe_session_id
  end

  test "adds to existing balance" do
    CreditBalance.create!(user: @user, balance: 3)

    GrantsCredits.call(
      user: @user,
      amount: 5,
      stripe_session_id: "cs_test_add"
    )

    assert_equal 8, @user.credit_balance.reload.balance
  end

  test "is idempotent on duplicate stripe_session_id" do
    GrantsCredits.call(
      user: @user,
      amount: 5,
      stripe_session_id: "cs_test_dupe"
    )

    assert_no_difference "CreditTransaction.count" do
      result = GrantsCredits.call(
        user: @user,
        amount: 5,
        stripe_session_id: "cs_test_dupe"
      )
      assert result.success?
    end

    assert_equal 5, @user.credit_balance.reload.balance
  end
end
