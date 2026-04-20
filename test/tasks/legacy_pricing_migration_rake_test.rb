require "test_helper"
require "rake"

class LegacyPricingMigrationRakeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("pricing:legacy_migration")
  end

  teardown do
    ENV.delete("DRY_RUN")
    ENV.delete("ONLY_EMAIL")
    Rake::Task["pricing:legacy_migration"].reenable
  end

  test "DRY_RUN scoped to ONLY_EMAIL makes no mutations and queues no emails" do
    user = users(:credit_user)
    ENV["DRY_RUN"] = "1"
    ENV["ONLY_EMAIL"] = user.email_address

    tx_count_before = CreditTransaction.count
    balance_before = user.credit_balance.balance

    assert_enqueued_emails 0 do
      output, = capture_io { Rake::Task["pricing:legacy_migration"].invoke }

      assert_match "DRY RUN", output
      assert_match user.email_address, output
      assert_match "bump #{balance_before} -> #{(balance_before * 2) + 20}", output
    end

    assert_equal tx_count_before, CreditTransaction.count
    user.credit_balance.reload
    assert_equal balance_before, user.credit_balance.balance
  end

  test "live run scoped to ONLY_EMAIL bumps balance and queues one email" do
    user = users(:credit_user)
    ENV["ONLY_EMAIL"] = user.email_address
    previous = user.credit_balance.balance
    expected_new = (previous * 2) + 20
    expected_bump = expected_new - previous

    assert_enqueued_emails 1 do
      capture_io { Rake::Task["pricing:legacy_migration"].invoke }
    end

    user.credit_balance.reload
    assert_equal expected_new, user.credit_balance.balance

    tx = CreditTransaction.find_by(
      stripe_session_id: "legacy_pricing_migration_2026_04_user_#{user.id}"
    )
    assert_not_nil tx, "expected a CreditTransaction tagged with the migration session id"
    assert_equal expected_bump, tx.amount
    assert_equal "purchase", tx.transaction_type
    assert_equal expected_new, tx.balance_after
  end

  test "live run without ONLY_EMAIL targets only non-complimentary, non-unlimited users with positive balance" do
    # credit_user is the only fixture with a positive credit_balance (3).
    # complimentary_user and unlimited_user are excluded by account_type.
    # jesse has a balance fixture but it's 0 — excluded by balance: 1...
    target = users(:credit_user)

    assert_enqueued_emails 1 do
      capture_io { Rake::Task["pricing:legacy_migration"].invoke }
    end

    target.credit_balance.reload
    assert_equal 26, target.credit_balance.balance, "credit_user starts at 3, expected (3*2)+20=26"

    assert CreditTransaction.exists?(
      stripe_session_id: "legacy_pricing_migration_2026_04_user_#{target.id}"
    )

    # Verify the excluded users weren't touched.
    assert_nil CreditTransaction.find_by(
      stripe_session_id: "legacy_pricing_migration_2026_04_user_#{users(:complimentary_user).id}"
    )
    assert_nil CreditTransaction.find_by(
      stripe_session_id: "legacy_pricing_migration_2026_04_user_#{users(:unlimited_user).id}"
    )
  end

  test "idempotent: running twice does not double-bump" do
    user = users(:credit_user)
    ENV["ONLY_EMAIL"] = user.email_address
    previous = user.credit_balance.balance
    expected_new = (previous * 2) + 20

    capture_io { Rake::Task["pricing:legacy_migration"].invoke }
    Rake::Task["pricing:legacy_migration"].reenable

    user.credit_balance.reload
    balance_after_first_run = user.credit_balance.balance
    tx_count_after_first_run = CreditTransaction.where(
      stripe_session_id: "legacy_pricing_migration_2026_04_user_#{user.id}"
    ).count

    # Second run should skip and queue no additional email.
    assert_enqueued_emails 0 do
      output, = capture_io { Rake::Task["pricing:legacy_migration"].invoke }
      assert_match "SKIP", output
      assert_match "already migrated", output
    end

    user.credit_balance.reload
    assert_equal expected_new, balance_after_first_run
    assert_equal expected_new, user.credit_balance.balance, "balance must not change on re-run"
    assert_equal 1, tx_count_after_first_run
    assert_equal 1, CreditTransaction.where(
      stripe_session_id: "legacy_pricing_migration_2026_04_user_#{user.id}"
    ).count, "CreditTransaction count must stay at 1 after re-run"
  end

  test "ONLY_EMAIL creates a credit_balance for a user who does not have one yet" do
    # Jesse's fixture has a balance of 0. Use a user without any credit_balance
    # to exercise the ONLY_EMAIL bootstrap path that creates the row.
    user = users(:free_user)
    assert_nil user.credit_balance, "sanity: free_user starts without a credit_balance"
    ENV["ONLY_EMAIL"] = user.email_address

    assert_enqueued_emails 1 do
      capture_io { Rake::Task["pricing:legacy_migration"].invoke }
    end

    user.reload
    assert_not_nil user.credit_balance
    assert_equal 20, user.credit_balance.balance, "expected (0*2)+20=20 for a fresh user"
  end
end
