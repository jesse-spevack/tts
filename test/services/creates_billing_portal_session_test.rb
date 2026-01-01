require "test_helper"

class CreatesBillingPortalSessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:subscriber)
    Stripe.api_key = "sk_test_fake"
  end

  test "creates portal session and returns URL" do
    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return(
        status: 200,
        body: { id: "bps_test", url: "https://billing.stripe.com/test" }.to_json
      )

    result = CreatesBillingPortalSession.call(
      user: @user,
      return_url: "https://example.com/billing"
    )

    assert result.success?
    assert_equal "https://billing.stripe.com/test", result.data
  end

  test "returns failure when user has no stripe_customer_id" do
    user = users(:free_user)

    result = CreatesBillingPortalSession.call(
      user: user,
      return_url: "https://example.com/billing"
    )

    refute result.success?
    assert_equal "No Stripe customer ID", result.error
  end

  test "returns failure on Stripe error" do
    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return(
        status: 400,
        body: { error: { message: "Customer not found", type: "invalid_request_error" } }.to_json
      )

    result = CreatesBillingPortalSession.call(
      user: @user,
      return_url: "https://example.com/billing"
    )

    refute result.success?
    assert_match(/Stripe error/, result.error)
  end
end
