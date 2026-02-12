# frozen_string_literal: true

require "test_helper"

class CreditBalanceTest < ActiveSupport::TestCase
  test "belongs to user" do
    balance = credit_balances(:with_credits)
    assert_equal users(:credit_user), balance.user
  end

  test "validates balance is not negative" do
    balance = CreditBalance.new(user: users(:one), balance: -1)
    refute balance.valid?
    assert_includes balance.errors[:balance], "must be greater than or equal to 0"
  end

  test ".for finds existing balance" do
    existing = credit_balances(:with_credits)
    found = CreditBalance.for(users(:credit_user))
    assert_equal existing, found
  end

  test ".for creates balance for user without one" do
    user = users(:subscriber)
    assert_nil user.credit_balance

    balance = CreditBalance.for(user)
    assert balance.persisted?
    assert_equal 0, balance.balance
  end

  test "sufficient? returns true when balance is positive" do
    balance = credit_balances(:with_credits)
    assert balance.sufficient?
  end

  test "sufficient? returns false when balance is zero" do
    balance = credit_balances(:empty_balance)
    refute balance.sufficient?
  end

  test "deduct! decrements balance by 1" do
    balance = credit_balances(:with_credits)
    assert_equal 3, balance.balance

    balance.deduct!
    assert_equal 2, balance.reload.balance
  end

  test "deduct! raises InsufficientCreditsError when balance is zero" do
    balance = credit_balances(:empty_balance)

    assert_raises(CreditBalance::InsufficientCreditsError) do
      balance.deduct!
    end
  end

  test "add! increments balance by given amount" do
    balance = credit_balances(:empty_balance)
    balance.add!(5)
    assert_equal 5, balance.reload.balance
  end

  test "add! works with existing positive balance" do
    balance = credit_balances(:with_credits)
    balance.add!(5)
    assert_equal 8, balance.reload.balance
  end
end
