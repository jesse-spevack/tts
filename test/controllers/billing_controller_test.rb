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
end
