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

  # --- Plan lookup (agent-team-bwz) ---

  test "plan_name returns human-readable name for monthly price" do
    subscription = subscriptions(:active_subscription)
    assert_equal "Premium Monthly", subscription.plan_name
  end

  test "plan_name returns human-readable name for annual price" do
    subscription = subscriptions(:annual_subscription)
    assert_equal "Premium Annual", subscription.plan_name
  end

  test "plan_name returns nil for unknown price id" do
    subscription = Subscription.new(stripe_price_id: "price_unknown")
    assert_nil subscription.plan_name
  end

  test "plan_display_price returns formatted price for monthly" do
    subscription = subscriptions(:active_subscription)
    assert_equal "$9/mo", subscription.plan_display_price
  end

  test "plan_display_price returns formatted price for annual" do
    subscription = subscriptions(:annual_subscription)
    assert_equal "$89/yr", subscription.plan_display_price
  end

  test "plan_display_price returns nil for unknown price id" do
    subscription = Subscription.new(stripe_price_id: "price_unknown")
    assert_nil subscription.plan_display_price
  end

  # --- Status pill presentation (agent-team-bwz) ---

  test "status_pill_label is 'Active' for active subscriptions" do
    subscription = subscriptions(:active_subscription)
    assert_equal "Active", subscription.status_pill_label
  end

  test "status_pill_label is 'Canceling' for canceling subscriptions" do
    subscription = subscriptions(:canceling_subscription)
    assert_equal "Canceling", subscription.status_pill_label
  end

  test "status_pill_label is 'Past Due' for past_due subscriptions" do
    subscription = subscriptions(:past_due_subscription)
    assert_equal "Past Due", subscription.status_pill_label
  end

  test "status_pill_label is 'Canceled' for canceled subscriptions" do
    subscription = subscriptions(:canceled_subscription)
    assert_equal "Canceled", subscription.status_pill_label
  end
end
