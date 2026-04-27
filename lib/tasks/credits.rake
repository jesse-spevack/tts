# frozen_string_literal: true

# Credit ledger reconciliation (agent-team-1pri, epic agent-team-vgmv).
#
# Asserts the invariant `credit_balances.balance == SUM(credit_transactions.amount)`
# per user. Logs one ERROR-level line per drifted user and exits non-zero so
# CI/ops treat drift as a build-breaking signal. Does NOT auto-heal — drift
# indicates a bug and silently fixing it masks the cause.
namespace :credits do
  desc "Verify credit_balances.balance equals SUM(credit_transactions.amount) per user; exit non-zero on drift"
  task reconcile: :environment do
    result = ReconcilesCredits.call
    drifts = result.data[:drifts]

    if drifts.empty?
      puts "credits:reconcile OK — 0 drifted users"
      next
    end

    drifts.each do |drift|
      message = "CreditDrift user_id=#{drift[:user_id]} " \
                "cached=#{drift[:cached]} " \
                "ledger=#{drift[:ledger]} " \
                "diff=#{drift[:diff]}"
      Rails.logger.error(message)
      puts message
    end

    puts "credits:reconcile FAILED — #{drifts.size} drifted user(s)"
    exit 1
  end
end
