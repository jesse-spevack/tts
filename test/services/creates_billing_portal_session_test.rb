require "test_helper"

class CreatesBillingPortalSessionTest < ActiveSupport::TestCase
  setup do
    Stripe.api_key = "sk_test_fake"
  end

  test "creates portal session and returns URL" do
    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return(
        status: 200,
        body: { id: "bps_test", url: "https://billing.stripe.com/test" }.to_json
      )

    result = CreatesBillingPortalSession.call(
      stripe_customer_id: "cus_test123",
      return_url: "https://example.com/billing"
    )

    assert result.success?
    assert_equal "https://billing.stripe.com/test", result.data
  end

  test "returns failure on Stripe error" do
    stub_request(:post, "https://api.stripe.com/v1/billing_portal/sessions")
      .to_return(
        status: 400,
        body: { error: { message: "Customer not found", type: "invalid_request_error" } }.to_json
      )

    result = CreatesBillingPortalSession.call(
      stripe_customer_id: "cus_invalid",
      return_url: "https://example.com/billing"
    )

    refute result.success?
    assert_match(/Stripe error/, result.error)
  end
end
