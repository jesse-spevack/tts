require "test_helper"

class DeactivationTest < ActiveSupport::TestCase
  test "is valid with user and deactivated_at" do
    record = Deactivation.new(user: users(:one), deactivated_at: Time.current)
    assert record.valid?
  end

  test "requires a user" do
    record = Deactivation.new(deactivated_at: Time.current)
    refute record.valid?
    assert record.errors[:user].any?
  end

  test "requires deactivated_at" do
    record = Deactivation.new(user: users(:one))
    refute record.valid?
    assert record.errors[:deactivated_at].any?
  end

  test "reason is optional" do
    record = Deactivation.new(user: users(:one), deactivated_at: Time.current)
    assert_nil record.reason
    assert record.valid?
  end

  test "queryable by user_id for support lookups (agent-team-k15)" do
    user = users(:one)
    Deactivation.create!(user: user, deactivated_at: Time.current)

    assert_equal 1, Deactivation.where(user_id: user.id).count
  end
end
