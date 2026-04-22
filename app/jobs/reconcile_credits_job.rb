# frozen_string_literal: true

# Nightly reconciliation job (agent-team-1pri, epic agent-team-vgmv).
#
# Scheduled from config/recurring.yml. Calls ReconcilesCredits and logs
# one ERROR-level line per drifted user so existing error reporting picks
# up the signal. Does not raise on drift — drift is a detected invariant
# violation, not a job execution failure. (The rake task uses non-zero
# exit as its signal; the scheduled job uses ERROR logs.)
class ReconcileCreditsJob < ApplicationJob
  queue_as :default

  def perform
    result = ReconcilesCredits.call
    drifts = result.data[:drifts]

    if drifts.empty?
      Rails.logger.info "[ReconcileCreditsJob] OK — 0 drifted users"
      return
    end

    drifts.each do |drift|
      Rails.logger.error(
        "CreditDrift user_id=#{drift[:user_id]} " \
        "cached=#{drift[:cached]} " \
        "ledger=#{drift[:ledger]} " \
        "diff=#{drift[:diff]}"
      )
    end

    Rails.logger.error "[ReconcileCreditsJob] FAILED — #{drifts.size} drifted user(s)"
  end
end
