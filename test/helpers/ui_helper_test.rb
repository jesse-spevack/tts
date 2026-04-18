# frozen_string_literal: true

require "test_helper"

class UiHelperTest < ActionView::TestCase
  include UiHelper

  # --- status_pill_label ---

  test "status_pill_label returns 'Active' for active subscription" do
    assert_equal "Active", status_pill_label(subscriptions(:active_subscription))
  end

  test "status_pill_label returns 'Canceling' for active subscription with cancel_at" do
    assert_equal "Canceling", status_pill_label(subscriptions(:canceling_subscription))
  end

  test "status_pill_label returns 'Past Due' for past_due subscription" do
    assert_equal "Past Due", status_pill_label(subscriptions(:past_due_subscription))
  end

  test "status_pill_label returns 'Canceled' for canceled subscription" do
    assert_equal "Canceled", status_pill_label(subscriptions(:canceled_subscription))
  end

  test "status_pill_label returns empty string for nil subscription" do
    assert_equal "", status_pill_label(nil)
  end

  # --- status_pill_classes ---

  test "status_pill_classes returns green classes for active subscription" do
    assert_equal(
      "bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-400",
      status_pill_classes(subscriptions(:active_subscription))
    )
  end

  test "status_pill_classes returns yellow classes for canceling subscription" do
    assert_equal(
      "bg-yellow-50 text-yellow-700 dark:bg-yellow-500/10 dark:text-yellow-400",
      status_pill_classes(subscriptions(:canceling_subscription))
    )
  end

  test "status_pill_classes returns yellow classes for past_due subscription" do
    assert_equal(
      "bg-yellow-50 text-yellow-700 dark:bg-yellow-500/10 dark:text-yellow-400",
      status_pill_classes(subscriptions(:past_due_subscription))
    )
  end

  test "status_pill_classes returns mist classes for canceled subscription" do
    assert_equal(
      "bg-mist-100 text-mist-600 dark:bg-mist-500/10 dark:text-mist-400",
      status_pill_classes(subscriptions(:canceled_subscription))
    )
  end

  test "status_pill_classes returns empty string for nil subscription" do
    assert_equal "", status_pill_classes(nil)
  end

  # --- manage_billing_cta_label ---

  test "manage_billing_cta_label returns 'Manage Billing' for active subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(subscriptions(:active_subscription))
  end

  test "manage_billing_cta_label returns 'Manage Billing' for canceling subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(subscriptions(:canceling_subscription))
  end

  test "manage_billing_cta_label returns 'Manage Billing' for past_due subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(subscriptions(:past_due_subscription))
  end

  test "manage_billing_cta_label returns 'Resubscribe' for canceled subscription" do
    assert_equal "Resubscribe", manage_billing_cta_label(subscriptions(:canceled_subscription))
  end

  test "manage_billing_cta_label returns 'Manage Billing' for nil subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(nil)
  end
end
