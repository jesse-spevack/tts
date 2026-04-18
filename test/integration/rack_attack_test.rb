require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    # Use unlimited user to avoid free tier episode limits (2/month)
    @user = users(:unlimited_user)
    @api_token = GeneratesApiToken.call(user: @user)
    @plain_token = @api_token.plain_token
    @valid_params = {
      source_type: "extension",
      title: "Test Article",
      author: "Test Author",
      description: "A test article description",
      content: "This is the full content of the article. " * 50,
      url: "https://example.com/article"
    }

    # Use a fresh memory store for each test
    @memory_store = ActiveSupport::Cache::MemoryStore.new
    @original_cache = Rack::Attack.cache.store
    Rack::Attack.cache.store = @memory_store
    Rack::Attack.reset!

    # Freeze time so rate limit windows don't shift mid-test
    freeze_time
  end

  teardown do
    unfreeze_time
    Rack::Attack.reset!
    Rack::Attack.cache.store = @original_cache
  end

  test "allows requests under the rate limit" do
    5.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/article-#{i}"),
        headers: auth_header(@plain_token),
        as: :json

      assert_response :created, "Request #{i + 1} should succeed"
    end
  end

  test "returns 429 when rate limit exceeded" do
    # Make 20 requests (the limit)
    20.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/article-#{i}"),
        headers: auth_header(@plain_token),
        as: :json

      assert_response :created, "Request #{i + 1} should succeed"
    end

    # The 21st request should be rate limited
    post api_v1_episodes_path,
      params: @valid_params.merge(url: "https://example.com/article-21"),
      headers: auth_header(@plain_token),
      as: :json

    assert_response :too_many_requests
  end

  test "returns Retry-After header when rate limited" do
    # Exceed rate limit
    21.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/article-#{i}"),
        headers: auth_header(@plain_token),
        as: :json
    end

    assert_response :too_many_requests
    assert response.headers["Retry-After"].present?
    assert_operator response.headers["Retry-After"].to_i, :>, 0
  end

  test "returns JSON error message when rate limited" do
    # Exceed rate limit
    21.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/article-#{i}"),
        headers: auth_header(@plain_token),
        as: :json
    end

    assert_response :too_many_requests
    json = response.parsed_body
    assert_equal "Rate limit exceeded. Please try again later.", json["error"]
  end

  test "rate limits are per-token" do
    # Create a second unlimited user with their own token
    other_user = users(:complimentary_user)
    other_token = GeneratesApiToken.call(user: other_user)

    # Make 20 requests for first user
    20.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/article-#{i}"),
        headers: auth_header(@plain_token),
        as: :json
    end

    # First user is rate limited
    post api_v1_episodes_path,
      params: @valid_params.merge(url: "https://example.com/article-21"),
      headers: auth_header(@plain_token),
      as: :json

    assert_response :too_many_requests

    # Second user can still make requests
    post api_v1_episodes_path,
      params: @valid_params.merge(url: "https://example.com/article-other"),
      headers: auth_header(other_token.plain_token),
      as: :json

    assert_response :created
  end

  # Unauthenticated episode creation rate limiting (MPP 402 challenge protection)

  test "unauthenticated POST requests are throttled after 10 per minute" do
    stub_stripe_payment_intent_creation

    10.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/anon-#{i}"),
        as: :json

      # Without auth, MppPayable returns 402 — that's fine, we just care about throttling
      refute_equal 429, response.status, "Request #{i + 1} should not be throttled"
    end

    # The 11th unauthenticated request should be rate limited
    post api_v1_episodes_path,
      params: @valid_params.merge(url: "https://example.com/anon-11"),
      as: :json

    assert_response :too_many_requests
  end

  test "authenticated Bearer token requests are not affected by unauthenticated throttle" do
    stub_stripe_payment_intent_creation

    # Exhaust the unauthenticated limit first (10 per minute)
    10.times do |i|
      post api_v1_episodes_path,
        params: @valid_params.merge(url: "https://example.com/anon-#{i}"),
        as: :json
    end

    # Authenticated request should still go through (different throttle key)
    post api_v1_episodes_path,
      params: @valid_params.merge(url: "https://example.com/auth-1"),
      headers: auth_header(@plain_token),
      as: :json

    assert_response :created
  end

  # Device code creation rate limiting

  test "allows device code creation under the rate limit" do
    5.times do
      post api_v1_auth_device_codes_path
      assert_response :ok
    end
  end

  test "rate limits device code creation" do
    5.times do
      post api_v1_auth_device_codes_path
      assert_response :ok
    end

    post api_v1_auth_device_codes_path
    assert_response :too_many_requests
  end

  # Device token polling rate limiting

  test "allows device token polling under the rate limit" do
    pending_code = device_codes(:pending)

    10.times do
      post api_v1_auth_device_tokens_path, params: { device_code: pending_code.device_code }
      assert_response :bad_request # authorization_pending
    end
  end

  test "rate limits device token polling" do
    pending_code = device_codes(:pending)

    30.times do
      post api_v1_auth_device_tokens_path, params: { device_code: pending_code.device_code }
      assert_response :bad_request
    end

    post api_v1_auth_device_tokens_path, params: { device_code: pending_code.device_code }
    assert_response :too_many_requests
  end

  private

  def auth_header(token)
    { "Authorization" => "Bearer #{token}" }
  end

  # Stub Stripe PaymentIntent creation for unauthenticated requests that
  # reach render_402_challenge -> Mpp::CreatesDepositAddress
  def stub_stripe_payment_intent_creation
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_#{SecureRandom.hex(8)}",
        object: "payment_intent",
        amount: 100,
        currency: "usd",
        status: "requires_action",
        next_action: {
          type: "crypto_display_details",
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xthrottle_test_deposit" }
            }
          }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })
  end
end
