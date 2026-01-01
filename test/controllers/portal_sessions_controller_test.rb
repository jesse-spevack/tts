require "test_helper"

class PortalSessionsControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  setup do
    Stripe.api_key = "sk_test_fake"
  end

  test "create redirects to Stripe" do
    user = users(:subscriber)
    sign_in_as(user)

    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return(status: 200, body: { url: "https://billing.stripe.com/test" }.to_json)

    post portal_session_path
    assert_redirected_to "https://billing.stripe.com/test"
  end

  test "create requires subscription" do
    sign_in_as(users(:free_user))
    post portal_session_path
    assert_redirected_to billing_path
    assert_equal "No active subscription", flash[:alert]
  end

  test "create requires authentication" do
    post portal_session_path
    assert_redirected_to root_path
  end
end
