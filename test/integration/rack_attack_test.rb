require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    # Use unlimited user to avoid free tier episode limits (2/month)
    @user = users(:unlimited_user)
    @api_token = ApiToken.generate_for(@user)
    @plain_token = @api_token.plain_token
    @valid_params = {
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
  end

  teardown do
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
    other_token = ApiToken.generate_for(other_user)

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

  private

  def auth_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
