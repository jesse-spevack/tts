require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "status enum has correct values" do
    assert_equal({ "active" => 0, "past_due" => 1, "canceled" => 2 }, Subscription.statuses)
  end

  test "belongs to user" do
    subscription = subscriptions(:active_subscription)
    assert_equal users(:subscriber), subscription.user
  end

  test "active? returns true for active subscriptions" do
    subscription = subscriptions(:active_subscription)
    assert subscription.active?
  end

  test "active? returns false for canceled subscriptions" do
    subscription = subscriptions(:canceled_subscription)
    refute subscription.active?
  end

  test "canceling? returns true when cancel_at is present" do
    subscription = Subscription.new(cancel_at: 1.month.from_now)
    assert subscription.canceling?
  end

  test "canceling? returns false when cancel_at is nil" do
    subscription = Subscription.new(cancel_at: nil)
    refute subscription.canceling?
  end
end
