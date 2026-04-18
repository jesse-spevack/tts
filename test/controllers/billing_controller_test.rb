require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  test "show requires authentication" do
    get billing_path
    assert_redirected_to root_path
  end

  test "show redirects free user to upgrade" do
    sign_in_as(users(:free_user))
    get billing_path
    assert_redirected_to upgrade_path
  end

  test "show renders for premium user" do
    sign_in_as(users(:subscriber))
    get billing_path
    assert_response :success
  end

  test "show displays 'Ends on' for subscription pending cancellation" do
    sign_in_as(users(:canceling_subscriber))
    get billing_path
    assert_response :success
    assert_match "Ends on", response.body
    refute_match "Renews on", response.body
  end

  test "show displays 'Renews on' for active renewing subscription" do
    sign_in_as(users(:subscriber))
    get billing_path
    assert_response :success
    assert_match "Renews on", response.body
  end

  # --- Gate widening for non-premium subscription states (agent-team-bwz) ---

  test "show renders for past_due subscriber (no credits, not premium)" do
    # Pre-bwz this redirected to /upgrade because free? = true. Now that
    # subscription.present? keeps them on /billing, they should land on the
    # past_due branch with Fix Payment button.
    sign_in_as(users(:past_due_subscriber))
    get billing_path
    assert_response :success
    assert_match "Past Due", response.body
    assert_match "Fix Payment", response.body
  end

  test "show renders for canceled subscriber (no credits, not premium)" do
    # Pre-bwz this redirected to /upgrade. Now that subscription.present? keeps
    # them on /billing, they should see the canceled branch + Resubscribe section.
    sign_in_as(users(:canceled_subscriber))
    get billing_path
    assert_response :success
    assert_match "Canceled", response.body
    assert_match "Resubscribe", response.body
  end
end
