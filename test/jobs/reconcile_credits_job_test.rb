# frozen_string_literal: true

require "test_helper"

# Tests for ReconcileCreditsJob (agent-team-1pri, epic agent-team-vgmv).
#
# The job runs nightly via config/recurring.yml. On drift it logs at
# ERROR level (existing error reporting picks that up) but does NOT
# raise — drift is a detected invariant violation, not a job failure.
class ReconcileCreditsJobTest < ActiveSupport::TestCase
  setup do
    CreditTransaction.delete_all
    CreditBalance.delete_all
  end

  test "logs INFO and does not raise when there is no drift" do
    user = User.create!(email_address: "job_clean@example.com", account_type: 0)
    CreditBalance.for(user).update!(balance: 4)
    CreditTransaction.create!(
      user: user, amount: 4, balance_after: 4,
      transaction_type: "purchase", stripe_session_id: "cs_job_clean"
    )

    messages = capture_logger { ReconcileCreditsJob.perform_now }

    assert_match(/0 drifted users/, messages.join("\n"))
  end

  test "logs an ERROR line per drift and does not raise" do
    user = User.create!(email_address: "job_drift@example.com", account_type: 0)
    CreditTransaction.create!(
      user: user, amount: 5, balance_after: 5,
      transaction_type: "purchase", stripe_session_id: "cs_job_drift"
    )
    CreditBalance.for(user).update_column(:balance, 50)

    messages = capture_logger(level: Logger::ERROR) { ReconcileCreditsJob.perform_now }

    joined = messages.join("\n")
    assert_match(
      /CreditDrift user_id=#{user.id} cached=50 ledger=5 diff=45/,
      joined
    )
    assert_match(/1 drifted user/, joined)
  end

  private

  # Captures log lines at the given level or above while the block runs.
  # We swap out Rails.logger for a StringIO-backed Logger so assertions can
  # inspect what was actually written.
  def capture_logger(level: Logger::DEBUG)
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(io)
    Rails.logger.level = level
    yield
    io.string.split("\n")
  ensure
    Rails.logger = original_logger
  end
end
