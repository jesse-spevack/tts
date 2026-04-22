# frozen_string_literal: true

require "test_helper"
require "rake"

# Tests for the `credits:reconcile` rake task (agent-team-1pri,
# epic agent-team-vgmv).
#
# The task exits 0 when every CreditBalance matches the SUM of its
# CreditTransaction amounts, and exits 1 with per-user ERROR logs when
# any user is drifted. Rake tasks must be re-enabled between invocations
# because Rake only runs each task once per process.
class CreditsRakeTest < ActiveSupport::TestCase
  TASK_NAME = "credits:reconcile"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    # Strip any fixture-inherited drift so tests start from a known-clean
    # invariant. The reconcile task scans EVERY balance, so leftover drift
    # from fixtures would make the happy-path test flaky.
    CreditTransaction.delete_all
    CreditBalance.delete_all
  end

  teardown do
    Rake::Task[TASK_NAME].reenable if Rake::Task.task_defined?(TASK_NAME)
  end

  test "exits 0 and prints OK when there is no drift" do
    user = User.create!(email_address: "rake_clean@example.com", account_type: 0)
    CreditBalance.for(user).update!(balance: 5)
    CreditTransaction.create!(
      user: user, amount: 5, balance_after: 5,
      transaction_type: "purchase", stripe_session_id: "cs_rake_clean"
    )

    output, = capture_io { Rake::Task[TASK_NAME].invoke }

    assert_match(/OK/, output)
    assert_match(/0 drifted/, output)
  end

  test "exits 1 and logs per-drift line when drift exists" do
    user = User.create!(email_address: "rake_drift@example.com", account_type: 0)
    CreditTransaction.create!(
      user: user, amount: 3, balance_after: 3,
      transaction_type: "purchase", stripe_session_id: "cs_rake_drift"
    )
    CreditBalance.for(user).update_column(:balance, 42)

    error = assert_raises(SystemExit) do
      capture_io { Rake::Task[TASK_NAME].invoke }
    end

    assert_equal 1, error.status
  end

  test "logs each drift in the agreed format" do
    user = User.create!(email_address: "rake_drift_fmt@example.com", account_type: 0)
    CreditTransaction.create!(
      user: user, amount: 2, balance_after: 2,
      transaction_type: "purchase", stripe_session_id: "cs_rake_drift_fmt"
    )
    CreditBalance.for(user).update_column(:balance, 10)

    assert_raises(SystemExit) do
      output, = capture_io { Rake::Task[TASK_NAME].invoke }
      # The rake task mirrors the ERROR log to stdout so operators running it
      # interactively can see drift without tailing the Rails log.
      assert_match(
        /CreditDrift user_id=#{user.id} cached=10 ledger=2 diff=8/,
        output
      )
    end
  end

  test "reports every drifted user when multiple drift" do
    u1 = User.create!(email_address: "rake_multi_1@example.com", account_type: 0)
    u2 = User.create!(email_address: "rake_multi_2@example.com", account_type: 0)

    CreditTransaction.create!(
      user: u1, amount: 5, balance_after: 5,
      transaction_type: "purchase", stripe_session_id: "cs_multi_1"
    )
    CreditBalance.for(u1).update_column(:balance, 7)

    CreditTransaction.create!(
      user: u2, amount: 9, balance_after: 9,
      transaction_type: "purchase", stripe_session_id: "cs_multi_2"
    )
    CreditBalance.for(u2).update_column(:balance, 1)

    assert_raises(SystemExit) do
      output, = capture_io { Rake::Task[TASK_NAME].invoke }
      assert_match(/user_id=#{u1.id}/, output)
      assert_match(/user_id=#{u2.id}/, output)
      assert_match(/2 drifted/, output)
    end
  end
end
