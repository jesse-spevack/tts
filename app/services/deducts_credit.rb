# frozen_string_literal: true

class DeductsCredit
  def self.call(user:, episode:)
    new(user:, episode:).call
  end

  def initialize(user:, episode:)
    @user = user
    @episode = episode
  end

  def call
    return Result.failure("No credits available") unless user.has_credits?

    balance = CreditBalance.for(user)
    balance.deduct!

    CreditTransaction.create!(
      user: user,
      amount: -1,
      balance_after: balance.balance,
      transaction_type: "usage",
      episode: episode
    )

    SendsCreditDepletedNudge.call(user: user) if balance.balance.zero?

    Result.success(balance)
  end

  private

  attr_reader :user, :episode
end
