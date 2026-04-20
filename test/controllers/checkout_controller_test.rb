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

    assert_redirected_to login_path(return_to: "/checkout")
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

    assert_redirected_to login_path(return_to: "/checkout")
  end

  # --- pack_size checkout routing (agent-team-qc7t) ---
  #
  # POST /checkout with pack_size: 5/10/20 looks up the matching pack in
  # AppConfig::Credits::PACKS and passes that pack's stripe_price_id to
  # CreatesCheckoutSession. The WebMock .with(body: hash_including(...))
  # assertions verify the correct price_id flows through to Stripe.

  test "create with pack_size 5 uses the 5-pack stripe price id" do
    sign_in_as(@user)
    pack_5_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 5 }[:stripe_price_id]

    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test" }.to_json)
    # WebMock is configured with query_values_notation = :flat (test_helper.rb),
    # which keeps Rack form bodies as flat keys rather than nesting them, so
    # we match "line_items[0][price]" literally instead of a nested hash.
    line_item_stub = stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .with(body: hash_including("line_items[0][price]" => pack_5_price_id))
      .to_return(status: 200, body: { id: "cs_5", url: "https://checkout.stripe.com/5" }.to_json)

    post checkout_path, params: { pack_size: 5 }

    assert_redirected_to "https://checkout.stripe.com/5"
    assert_requested line_item_stub
  end

  test "create with pack_size 10 uses the 10-pack stripe price id" do
    sign_in_as(@user)
    pack_10_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 10 }[:stripe_price_id]

    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test" }.to_json)
    line_item_stub = stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .with(body: hash_including("line_items[0][price]" => pack_10_price_id))
      .to_return(status: 200, body: { id: "cs_10", url: "https://checkout.stripe.com/10" }.to_json)

    post checkout_path, params: { pack_size: 10 }

    assert_redirected_to "https://checkout.stripe.com/10"
    assert_requested line_item_stub
  end

  test "create with pack_size 20 uses the 20-pack stripe price id" do
    sign_in_as(@user)
    pack_20_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 20 }[:stripe_price_id]

    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test" }.to_json)
    line_item_stub = stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .with(body: hash_including("line_items[0][price]" => pack_20_price_id))
      .to_return(status: 200, body: { id: "cs_20", url: "https://checkout.stripe.com/20" }.to_json)

    post checkout_path, params: { pack_size: 20 }

    assert_redirected_to "https://checkout.stripe.com/20"
    assert_requested line_item_stub
  end

  test "create with invalid integer pack_size does not call Stripe" do
    sign_in_as(@user)

    # No Stripe stub — if the controller reaches Stripe we want WebMock to blow up.
    post checkout_path, params: { pack_size: 7 }

    assert_redirected_to billing_path
    refute_nil flash[:alert], "expected a flash alert for invalid pack_size"
  end

  test "create with non-numeric pack_size does not call Stripe" do
    sign_in_as(@user)

    post checkout_path, params: { pack_size: "xyz" }

    assert_redirected_to billing_path
    refute_nil flash[:alert], "expected a flash alert for invalid pack_size"
  end

  test "create with pack_size requires authentication" do
    post checkout_path, params: { pack_size: 5 }

    assert_redirected_to login_path(return_to: "/checkout")
  end

  # --- GET /checkout?pack_size=N (agent-team-9dn7) ---
  #
  # Live caller: SessionsController#post_login_path does
  # `redirect_to checkout_path(pack_size: size)` after a credit_pack magic-link
  # auth. That's a GET with pack_size in the query string, which lands in
  # CheckoutController#show. This test closes the coverage gap on that branch.

  test "show with pack_size 5 uses the 5-pack stripe price id" do
    sign_in_as(@user)
    pack_5_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 5 }[:stripe_price_id]

    stub_request(:get, /api\.stripe\.com\/v1\/customers/)
      .to_return(status: 200, body: { data: [] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test" }.to_json)
    line_item_stub = stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .with(body: hash_including("line_items[0][price]" => pack_5_price_id))
      .to_return(status: 200, body: { id: "cs_5", url: "https://checkout.stripe.com/5" }.to_json)

    get checkout_path, params: { pack_size: 5 }

    assert_redirected_to "https://checkout.stripe.com/5"
    assert_requested line_item_stub
  end

  test "show with invalid pack_size redirects to billing with alert" do
    sign_in_as(@user)

    get checkout_path, params: { pack_size: 7 }

    assert_redirected_to billing_path
    refute_nil flash[:alert], "expected a flash alert for invalid pack_size"
  end
end
