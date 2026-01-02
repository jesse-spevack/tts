require "test_helper"

class CheckoutControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "create redirects to Stripe checkout" do
    sign_in_as(@user)

    # Mock Stripe API calls
    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test" }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.com/test" }.to_json)

    post checkout_path, params: { price_id: AppConfig::Stripe::PRICE_ID_MONTHLY }

    assert_redirected_to "https://checkout.stripe.com/test"
  end

  test "create with invalid price redirects back with error" do
    sign_in_as(@user)

    post checkout_path, params: { price_id: "invalid" }

    assert_redirected_to billing_path
    assert_equal "Invalid price selected", flash[:alert]
  end

  test "create requires authentication" do
    post checkout_path, params: { price_id: AppConfig::Stripe::PRICE_ID_MONTHLY }

    assert_redirected_to root_path
  end

  test "success page renders" do
    sign_in_as(@user)

    get checkout_success_path

    assert_response :success
  end

  test "cancel redirects to billing" do
    sign_in_as(@user)

    get checkout_cancel_path

    assert_redirected_to billing_path
  end

  test "show redirects to Stripe checkout with valid price_id" do
    sign_in_as(@user)

    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test" }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.com/test" }.to_json)

    get checkout_path, params: { price_id: AppConfig::Stripe::PRICE_ID_MONTHLY }

    assert_redirected_to "https://checkout.stripe.com/test"
  end

  test "show with invalid price redirects to billing with error" do
    sign_in_as(@user)

    get checkout_path, params: { price_id: "invalid" }

    assert_redirected_to billing_path
    assert_equal "Invalid price selected", flash[:alert]
  end

  test "show without price_id redirects to billing" do
    sign_in_as(@user)

    get checkout_path

    assert_redirected_to billing_path
    assert_equal "No plan selected", flash[:alert]
  end

  test "show requires authentication" do
    get checkout_path, params: { price_id: AppConfig::Stripe::PRICE_ID_MONTHLY }

    assert_redirected_to root_path
  end
end
