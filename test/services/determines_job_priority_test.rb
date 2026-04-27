# frozen_string_literal: true

require "test_helper"

class DeterminesJobPriorityTest < ActiveSupport::TestCase
  test "returns 0 for complimentary user" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:complimentary_user))
  end

  test "returns 0 for unlimited user" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:unlimited_user))
  end

  test "returns 10 for free user" do
    assert_equal 10, DeterminesJobPriority.call(user: users(:free_user))
  end

  # Regression guard (agent-team-hagg): after the 2026-04 pricing pivot,
  # credit-buying became a paid tier. Credit-paying users must enqueue at
  # PREMIUM_PRIORITY, not behind free-tier users at FREE_PRIORITY.
  test "returns 0 for credit-paying user" do
    assert_equal 0, DeterminesJobPriority.call(user: users(:credit_user))
  end
end
