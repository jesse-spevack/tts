# frozen_string_literal: true

require "test_helper"

class CreditTransactionTest < ActiveSupport::TestCase
  test "belongs to user" do
    transaction = credit_transactions(:purchase)
    assert_equal users(:credit_user), transaction.user
  end

  test "episode is optional" do
    transaction = credit_transactions(:purchase)
    assert_nil transaction.episode
  end

  test "usage transaction can reference episode" do
    transaction = CreditTransaction.create!(
      user: users(:credit_user),
      amount: -1,
      balance_after: 2,
      transaction_type: "usage",
      episode: episodes(:one)
    )
    assert_equal episodes(:one), transaction.episode
  end

  test "validates amount is present" do
    transaction = CreditTransaction.new(
      user: users(:free_user),
      balance_after: 5,
      transaction_type: "purchase"
    )
    refute transaction.valid?
    assert_includes transaction.errors[:amount], "can't be blank"
  end

  test "validates balance_after is present" do
    transaction = CreditTransaction.new(
      user: users(:free_user),
      amount: 5,
      transaction_type: "purchase"
    )
    refute transaction.valid?
    assert_includes transaction.errors[:balance_after], "can't be blank"
  end

  test "validates balance_after is not negative" do
    transaction = CreditTransaction.new(
      user: users(:free_user),
      amount: -1,
      balance_after: -1,
      transaction_type: "usage"
    )
    refute transaction.valid?
    assert_includes transaction.errors[:balance_after], "must be greater than or equal to 0"
  end

  test "validates transaction_type is present" do
    transaction = CreditTransaction.new(
      user: users(:free_user),
      amount: 5,
      balance_after: 5
    )
    refute transaction.valid?
    assert_includes transaction.errors[:transaction_type], "can't be blank"
  end

  test "validates transaction_type is purchase or usage" do
    transaction = CreditTransaction.new(
      user: users(:free_user),
      amount: 5,
      balance_after: 5,
      transaction_type: "refund"
    )
    refute transaction.valid?
    assert_includes transaction.errors[:transaction_type], "is not included in the list"
  end

  test "validates stripe_session_id uniqueness" do
    CreditTransaction.create!(
      user: users(:one),
      amount: 5,
      balance_after: 5,
      transaction_type: "purchase",
      stripe_session_id: "cs_unique_test"
    )

    duplicate = CreditTransaction.new(
      user: users(:two),
      amount: 5,
      balance_after: 5,
      transaction_type: "purchase",
      stripe_session_id: "cs_unique_test"
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:stripe_session_id], "has already been taken"
  end

  test "allows nil stripe_session_id for usage transactions" do
    transaction = CreditTransaction.new(
      user: users(:free_user),
      amount: -1,
      balance_after: 2,
      transaction_type: "usage",
      episode: episodes(:one),
      stripe_session_id: nil
    )
    assert transaction.valid?
  end
end
