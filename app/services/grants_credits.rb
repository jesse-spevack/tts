# frozen_string_literal: true

class GrantsCredits
  def self.call(user:, amount:, stripe_session_id:)
    new(user:, amount:, stripe_session_id:).call
  end

  def initialize(user:, amount:, stripe_session_id:)
    @user = user
    @amount = amount
    @stripe_session_id = stripe_session_id
  end

  def call
    return Result.success if already_granted?

    balance = CreditBalance.for(user)
    balance.add!(amount)

    CreditTransaction.create!(
      user: user,
      amount: amount,
      balance_after: balance.balance,
      transaction_type: "purchase",
      stripe_session_id: stripe_session_id
    )

    Result.success(balance)
  end

  private

  attr_reader :user, :amount, :stripe_session_id

  def already_granted?
    CreditTransaction.exists?(stripe_session_id: stripe_session_id)
  end
end
