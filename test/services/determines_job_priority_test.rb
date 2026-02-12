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
end
