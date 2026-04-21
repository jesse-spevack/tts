# frozen_string_literal: true

class RefundsCreditDebit
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    usage_txn = CreditTransaction.where(episode_id: episode.id, transaction_type: "usage").first
    return unless usage_txn

    GrantsCredits.call(
      user: episode.user,
      amount: usage_txn.amount.abs,
      stripe_session_id: "refund_#{usage_txn.id}"
    )
  end

  private

  attr_reader :episode
end
