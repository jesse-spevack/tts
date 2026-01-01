require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  setup do
    Stripe.api_key = "sk_test_fake"
  end

  test "show requires authentication" do
    get billing_path
    assert_redirected_to root_path
  end

  test "show renders for free user" do
    sign_in_as(users(:free_user))
    get billing_path
    assert_response :success
  end

  test "show renders for premium user" do
    sign_in_as(users(:subscriber))
    get billing_path
    assert_response :success
  end

  test "portal redirects to Stripe" do
    user = users(:subscriber)
    sign_in_as(user)

    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return(status: 200, body: { url: "https://billing.stripe.com/test" }.to_json)

    post billing_portal_path
    assert_redirected_to "https://billing.stripe.com/test"
  end

  test "portal requires subscription" do
    sign_in_as(users(:free_user))
    post billing_portal_path
    assert_redirected_to billing_path
    assert_equal "No active subscription", flash[:alert]
  end
end
