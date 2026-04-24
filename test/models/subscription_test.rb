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

  # --- PLAN_INFO drift detection (agent-team-01q.1) ---

  test "plan_name logs a structured warning when stripe_price_id is not in PLAN_INFO" do
    subscription = subscriptions(:active_subscription)
    subscription.update_column(:stripe_price_id, "price_drift_unknown")

    log_output = capture_logs do
      assert_nil subscription.plan_name
    end

    assert_match(/event=subscription_plan_info_miss/, log_output)
    assert_match(/user_id=#{subscription.user_id}/, log_output)
    assert_match(/stripe_price_id=price_drift_unknown/, log_output)
  end

  test "plan_display_price logs a structured warning when stripe_price_id is not in PLAN_INFO" do
    subscription = subscriptions(:active_subscription)
    subscription.update_column(:stripe_price_id, "price_drift_other")

    log_output = capture_logs do
      assert_nil subscription.plan_display_price
    end

    assert_match(/event=subscription_plan_info_miss/, log_output)
    assert_match(/stripe_price_id=price_drift_other/, log_output)
  end

  test "plan lookup does not log when stripe_price_id is in PLAN_INFO" do
    subscription = subscriptions(:active_subscription)

    log_output = capture_logs do
      subscription.plan_name
      subscription.plan_display_price
    end

    refute_match(/subscription_plan_info_miss/, log_output)
  end

  private

  def capture_logs
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end
