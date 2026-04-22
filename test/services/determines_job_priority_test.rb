# frozen_string_literal: true

require "test_helper"

class DeterminesJobPriorityTest < ActiveSupport::TestCase
  test "returns 0 for user with active subscription" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:subscriber))
  end

  test "returns 0 for complimentary user" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:complimentary_user))
  end

  test "returns 0 for unlimited user" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:unlimited_user))
  end

  test "returns 10 for free user" do
    assert_equal 10, DeterminesJobPriority.call(user: users(:free_user))
  end

  test "returns 10 for user with canceled subscription" do
    assert_equal 10, DeterminesJobPriority.call(user: users(:canceled_subscriber))
  end

  test "returns 10 for user with past_due subscription" do
    assert_equal 10, DeterminesJobPriority.call(user: users(:past_due_subscriber))
  end

  test "returns 0 for user with canceling subscription" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:canceling_subscriber))
  end

  # Regression guard (agent-team-hagg): after the 2026-04 pricing pivot,
  # credit-buying became a paid tier. Credit-paying users must enqueue at
  # PREMIUM_PRIORITY, not behind free-tier users at FREE_PRIORITY.
  test "returns 0 for credit-paying user" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:credit_user))
  end
end
