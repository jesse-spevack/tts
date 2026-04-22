# frozen_string_literal: true

# Checks the invariant `credit_balances.balance == SUM(credit_transactions.amount)`
# for every user. Returns a Result whose :data is `{ drifts: [...] }` where each
# drift is `{ user_id:, cached:, ledger:, diff: }`. `diff` is `cached - ledger`,
# so a positive diff means the cached balance is higher than the ledger (user
# got credits without a transaction row; the exact atomicity bug the parent
# epic agent-team-vgmv addresses).
#
# Observation-only: this service never mutates balances or transactions.
# Auto-healing was deliberately deferred — see epic design notes. Callers
# (the `credits:reconcile` rake task and ReconcileCreditsJob) decide how to
# react to drift (log, alert, exit non-zero, etc.).
#
# Performance: one GROUP BY query for ledger sums + one find_each over
# CreditBalance. Orphan ledger rows (user has transactions but no
# CreditBalance row) are picked up via a set-difference check on user_ids.
class ReconcilesCredits
  def self.call
    new.call
  end

  def call
    ledger_sums = CreditTransaction.group(:user_id).sum(:amount)
    drifts = []

    CreditBalance.find_each do |balance|
      ledger = ledger_sums.fetch(balance.user_id, 0)
      next if balance.balance == ledger

      drifts << {
        user_id: balance.user_id,
        cached: balance.balance,
        ledger: ledger,
        diff: balance.balance - ledger
      }
    end

    # Orphan ledger users: have transactions but no CreditBalance row.
    # Treat missing cached value as 0 — the invariant is "cached == ledger",
    # and 0 != non-zero ledger is drift.
    balance_user_ids = CreditBalance.pluck(:user_id).to_set
    ledger_sums.each do |user_id, ledger|
      next if balance_user_ids.include?(user_id)
      next if ledger.zero?

      drifts << {
        user_id: user_id,
        cached: 0,
        ledger: ledger,
        diff: -ledger
      }
    end

    Result.success(drifts: drifts)
  end
end
