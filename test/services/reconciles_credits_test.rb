# frozen_string_literal: true

require "test_helper"

# Tests for ReconcilesCredits (agent-team-1pri, epic agent-team-vgmv).
#
# Invariant: credit_balances.balance == SUM(credit_transactions.amount)
# for each user_id. The service returns a Result whose :data is a hash
# with :drifts — an array of { user_id:, cached:, ledger:, diff: } for
# every user whose cached balance disagrees with the ledger sum.
#
# The service is observation-only: it does NOT mutate balances or
# transactions (auto-healing is an explicitly deferred decision — see
# epic design notes).
class ReconcilesCreditsTest < ActiveSupport::TestCase
  # Use isolated users/balances so we don't have to unwind the fixture
  # drift baked into test/fixtures/credit_balances.yml (credit_user has
  # balance=3 but ledger=+5-1=4 — intentional state for other tests).
  setup do
    @clean_user = User.create!(email_address: "reconcile_clean@example.com", account_type: 0)
    @drift_user = User.create!(email_address: "reconcile_drift@example.com", account_type: 0)
  end

  test "returns success with empty drifts when every balance matches its ledger" do
    balance = CreditBalance.for(@clean_user)
    balance.update!(balance: 5)
    CreditTransaction.create!(
      user: @clean_user,
      amount: 5,
      balance_after: 5,
      transaction_type: "purchase",
      stripe_session_id: "cs_reconcile_clean_1"
    )

    result = ReconcilesCredits.call

    assert result.success?
    drifts = result.data[:drifts]
    refute_includes drifts.map { |d| d[:user_id] }, @clean_user.id
  end

  test "detects drift when cached balance exceeds ledger sum" do
    balance = CreditBalance.for(@drift_user)
    # Ledger says +3 total, cached balance says 99 — simulate the exact
    # atomicity bug the epic is guarding against: the balance mutated but
    # the ledger insert never happened.
    CreditTransaction.create!(
      user: @drift_user,
      amount: 3,
      balance_after: 3,
      transaction_type: "purchase",
      stripe_session_id: "cs_reconcile_drift_1"
    )
    balance.update_column(:balance, 99)

    result = ReconcilesCredits.call

    assert result.success?
    drift = result.data[:drifts].find { |d| d[:user_id] == @drift_user.id }
    assert drift, "expected drift for drift_user in #{result.data[:drifts].inspect}"
    assert_equal 99, drift[:cached]
    assert_equal 3, drift[:ledger]
    assert_equal 96, drift[:diff]
  end

  test "detects drift when cached balance is less than ledger sum" do
    balance = CreditBalance.for(@drift_user)
    CreditTransaction.create!(
      user: @drift_user,
      amount: 10,
      balance_after: 10,
      transaction_type: "purchase",
      stripe_session_id: "cs_reconcile_drift_2"
    )
    balance.update_column(:balance, 2)

    result = ReconcilesCredits.call

    drift = result.data[:drifts].find { |d| d[:user_id] == @drift_user.id }
    assert drift
    assert_equal 2, drift[:cached]
    assert_equal 10, drift[:ledger]
    assert_equal(-8, drift[:diff])
  end

  test "reports each drifted user separately in a multi-user scenario" do
    other = User.create!(email_address: "reconcile_other@example.com", account_type: 0)

    # clean user: balance matches ledger
    CreditBalance.for(@clean_user).update!(balance: 4)
    CreditTransaction.create!(
      user: @clean_user, amount: 4, balance_after: 4,
      transaction_type: "purchase", stripe_session_id: "cs_multi_clean"
    )

    # drift_user: positive drift
    CreditTransaction.create!(
      user: @drift_user, amount: 5, balance_after: 5,
      transaction_type: "purchase", stripe_session_id: "cs_multi_a"
    )
    CreditBalance.for(@drift_user).update_column(:balance, 7)

    # other: negative drift
    CreditTransaction.create!(
      user: other, amount: 8, balance_after: 8,
      transaction_type: "purchase", stripe_session_id: "cs_multi_b"
    )
    CreditBalance.for(other).update_column(:balance, 1)

    result = ReconcilesCredits.call

    user_ids = result.data[:drifts].map { |d| d[:user_id] }
    assert_includes user_ids, @drift_user.id
    assert_includes user_ids, other.id
    refute_includes user_ids, @clean_user.id
  end

  test "zero-balance user with no ledger entries is not drift" do
    CreditBalance.for(@clean_user).update!(balance: 0)

    result = ReconcilesCredits.call

    drift = result.data[:drifts].find { |d| d[:user_id] == @clean_user.id }
    assert_nil drift, "zero balance with zero ledger should not be reported"
  end

  test "user with negative transactions summing correctly is not drift" do
    # Realistic ledger: +5 purchase, -1 usage, -1 usage → balance 3
    CreditTransaction.create!(
      user: @clean_user, amount: 5, balance_after: 5,
      transaction_type: "purchase", stripe_session_id: "cs_neg_clean"
    )
    CreditTransaction.create!(
      user: @clean_user, amount: -1, balance_after: 4,
      transaction_type: "usage"
    )
    CreditTransaction.create!(
      user: @clean_user, amount: -1, balance_after: 3,
      transaction_type: "usage"
    )
    CreditBalance.for(@clean_user).update!(balance: 3)

    result = ReconcilesCredits.call

    drift = result.data[:drifts].find { |d| d[:user_id] == @clean_user.id }
    assert_nil drift
  end

  test "flags user who has ledger entries but no CreditBalance row" do
    # Orphan ledger: data corruption / manual DB tinker. The reconciler
    # should still surface this — the invariant cares about "cached ==
    # ledger", and "no cached row" != "ledger sum > 0".
    orphan = User.create!(email_address: "reconcile_orphan@example.com", account_type: 0)
    CreditTransaction.create!(
      user: orphan, amount: 7, balance_after: 7,
      transaction_type: "purchase", stripe_session_id: "cs_orphan"
    )
    # Do NOT create a CreditBalance row for this user.
    assert_nil CreditBalance.find_by(user_id: orphan.id)

    result = ReconcilesCredits.call

    drift = result.data[:drifts].find { |d| d[:user_id] == orphan.id }
    assert drift, "orphan ledger user should be flagged as drift"
    assert_equal 0, drift[:cached]
    assert_equal 7, drift[:ledger]
    assert_equal(-7, drift[:diff])
  end

  test "does not mutate balances or transactions" do
    CreditTransaction.create!(
      user: @drift_user, amount: 5, balance_after: 5,
      transaction_type: "purchase", stripe_session_id: "cs_no_mutate"
    )
    CreditBalance.for(@drift_user).update_column(:balance, 99)

    balance_before = CreditBalance.find_by(user_id: @drift_user.id).balance
    tx_count_before = CreditTransaction.where(user_id: @drift_user.id).count

    ReconcilesCredits.call

    assert_equal balance_before, CreditBalance.find_by(user_id: @drift_user.id).balance
    assert_equal tx_count_before, CreditTransaction.where(user_id: @drift_user.id).count
  end
end
