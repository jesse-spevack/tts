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

    ActiveRecord::Base.transaction do
      balance.add!(amount)

      CreditTransaction.create!(
        user: user,
        amount: amount,
        balance_after: balance.balance,
        transaction_type: "purchase",
        stripe_session_id: stripe_session_id
      )
    end

    Result.success(balance)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent webhook retry raced us and inserted the transaction first.
    # The unique index on credit_transactions.stripe_session_id rolled back
    # our balance.add!, so treat this as the already-granted path.
    Result.success
  end

  private

  attr_reader :user, :amount, :stripe_session_id

  def already_granted?
    CreditTransaction.exists?(stripe_session_id: stripe_session_id)
  end
end
