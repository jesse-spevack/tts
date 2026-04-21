# frozen_string_literal: true

# Unified refund orchestrator for SynthesizableContent. Replaces the three
# previous narrow refund paths (free-tier counter, credit re-grant, MPP
# Stripe refund) with one explicit call site per failure path.
#
# Dispatch priority:
#   1. content.mpp_payment.present?  → Mpp::RefundsPayment (Stripe refund).
#   2. Episode with usage CreditTransaction → GrantsCredits (idempotent via
#      stripe_session_id = "refund_<usage_txn_id>").
#   3. Episode owned by free-tier user → EpisodeUsage#decrement! (clamps at 0).
class RefundsPayment
  def self.call(content:)
    new(content: content).call
  end

  def initialize(content:)
    @content = content
  end

  def call
    return Mpp::RefundsPayment.call(mpp_payment: @content.mpp_payment) if @content.mpp_payment.present?

    if (txn = usage_txn)
      return GrantsCredits.call(
        user: @content.user,
        amount: txn.amount.abs,
        stripe_session_id: "refund_#{txn.id}"
      )
    end

    return unless @content.respond_to?(:user) && @content.user&.free?

    usage = EpisodeUsage.current_for(@content.user)
    usage.decrement! if usage.persisted?
  end

  private

  def usage_txn
    return unless @content.is_a?(Episode)
    CreditTransaction.find_by(episode_id: @content.id, transaction_type: "usage")
  end
end
