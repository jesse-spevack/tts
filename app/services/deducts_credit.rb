# frozen_string_literal: true

class DeductsCredit
  def self.call(user:, episode:, cost_in_credits:)
    new(user: user, episode: episode, cost_in_credits: cost_in_credits).call
  end

  def initialize(user:, episode:, cost_in_credits:)
    @user = user
    @episode = episode
    @cost_in_credits = cost_in_credits
  end

  def call
    balance = CreditBalance.for(user)
    return Result.failure("No credits available", code: :insufficient_credits) if balance.balance < cost_in_credits

    ActiveRecord::Base.transaction do
      balance.deduct!(cost_in_credits)

      CreditTransaction.create!(
        user: user,
        amount: -cost_in_credits,
        balance_after: balance.balance,
        transaction_type: "usage",
        episode: episode
      )

      SendsCreditDepletedNudge.call(user: user) if balance.balance.zero?
    end

    Result.success(balance)
  rescue CreditBalance::InsufficientCreditsError
    Result.failure("No credits available", code: :insufficient_credits)
  end

  private

  attr_reader :user, :episode, :cost_in_credits
end
