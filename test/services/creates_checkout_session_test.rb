require "test_helper"

class CreatesCheckoutSessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "creates checkout session and returns URL" do
    # Mock customer list (no existing customer)
    stub_request(:get, "https://api.stripe.com/v1/customers")
      .with(query: hash_including(email: @user.email_address))
      .to_return(status: 200, body: { data: [] }.to_json)

    # Mock customer create
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test123", email: @user.email_address }.to_json)

    # Mock checkout session create
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.com/test" }.to_json)

    result = CreatesCheckoutSession.call(
      user: @user,
      price_id: "price_test",
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel"
    )

    assert result.success?
    assert_equal "https://checkout.stripe.com/test", result.data
    assert_equal "cus_test123", @user.reload.stripe_customer_id
  end

  test "uses existing stripe_customer_id from user" do
    @user.update!(stripe_customer_id: "cus_saved")

    # Should NOT call customer list or create - goes straight to checkout
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.com/test" }.to_json)

    result = CreatesCheckoutSession.call(
      user: @user,
      price_id: "price_test",
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel"
    )

    assert result.success?
  end

  test "reuses existing Stripe customer and saves to user" do
    # Mock customer list (existing customer found)
    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [ { id: "cus_existing", email: @user.email_address } ] }.to_json)

    # Mock checkout session create
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.com/test" }.to_json)

    result = CreatesCheckoutSession.call(
      user: @user,
      price_id: "price_test",
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel"
    )

    assert result.success?
    assert_equal "cus_existing", @user.reload.stripe_customer_id
  end
end
