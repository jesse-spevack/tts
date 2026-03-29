# frozen_string_literal: true

require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = Doorkeeper::Application.create!(
      name: "Test MCP Client",
      uid: "test_mcp_client",
      redirect_uri: "http://localhost:3001/callback",
      scopes: "podread",
      confidential: false
    )
    @token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )
  end

  # --- Authentication tests ---

  test "returns 401 without token" do
    post "/mcp",
      params: jsonrpc_request("initialize"),
      headers: mcp_headers
    assert_response :unauthorized
  end

  test "returns 401 with expired token" do
    @token.update!(expires_in: 0, created_at: 2.hours.ago)

    post "/mcp",
      params: jsonrpc_request("initialize"),
      headers: mcp_headers(token: @token.token)
    assert_response :unauthorized
  end

  test "returns 401 with revoked token" do
    @token.revoke

    post "/mcp",
      params: jsonrpc_request("initialize"),
      headers: mcp_headers(token: @token.token)
    assert_response :unauthorized
  end

  test "401 response includes WWW-Authenticate with resource_metadata" do
    post "/mcp",
      params: jsonrpc_request("initialize"),
      headers: mcp_headers
    assert_response :unauthorized
    assert_match "resource_metadata", response.headers["WWW-Authenticate"]
    assert_match "oauth-protected-resource", response.headers["WWW-Authenticate"]
  end

  # --- Initialize ---

  test "initialize returns server info" do
    post "/mcp",
      params: jsonrpc_request("initialize", { protocolVersion: "2025-11-25", capabilities: {} }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_jsonrpc_result
    assert_equal "podread", result["serverInfo"]["name"]
    assert result["capabilities"]["tools"].present?
  end

  # --- tools/list ---

  test "lists all 7 tools" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_request("tools/list"),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_jsonrpc_result
    tool_names = result["tools"].map { |t| t["name"] }
    assert_equal 7, tool_names.size
    assert_includes tool_names, "create_episode_from_url"
    assert_includes tool_names, "create_episode_from_text"
    assert_includes tool_names, "list_episodes"
    assert_includes tool_names, "get_episode"
    assert_includes tool_names, "delete_episode"
    assert_includes tool_names, "get_feed_url"
    assert_includes tool_names, "list_voices"
  end

  # --- list_episodes ---

  test "list_episodes returns user episodes" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_tool_call("list_episodes"),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert data["episodes"].is_a?(Array)
    assert data["meta"]["total"].is_a?(Integer)
  end

  # --- get_episode ---

  test "get_episode returns episode details" do
    initialize_session!

    episode = @user.episodes.first
    skip "No fixtures for user one's episodes" unless episode

    post "/mcp",
      params: jsonrpc_tool_call("get_episode", { id: episode.prefix_id }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal episode.prefix_id, data["id"]
  end

  test "get_episode returns error for nonexistent episode" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_tool_call("get_episode", { id: "ep_nonexistent" }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "not_found", data["error"]
  end

  # --- list_voices ---

  test "list_voices returns available voices" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_tool_call("list_voices"),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert data["voices"].is_a?(Array)
    assert data["voices"].first["id"].present?
    assert data["voices"].first["name"].present?
  end

  # --- get_feed_url ---

  test "get_feed_url returns feed URL" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_tool_call("get_feed_url"),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert data["feed_url"].present?
  end

  # --- create_episode_from_url ---

  test "create_episode_from_url creates episode" do
    initialize_session!

    stub_request(:any, /.*/).to_return(status: 200, body: "Article content here " * 100)

    post "/mcp",
      params: jsonrpc_tool_call("create_episode_from_url", { url: "https://example.com/article" }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert data["id"].present?
    assert_equal "processing", data["status"]
  end

  # --- create_episode_from_text ---

  test "create_episode_from_text creates episode" do
    initialize_session!

    long_text = "This is a test article that needs to be converted into a podcast episode. " * 20

    post "/mcp",
      params: jsonrpc_tool_call("create_episode_from_text", {
        text: long_text,
        title: "Test Episode"
      }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert data["id"].present?
    assert_equal "processing", data["status"]
  end

  # --- delete_episode ---

  test "delete_episode returns error for nonexistent episode" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_tool_call("delete_episode", { id: "ep_nonexistent" }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "not_found", data["error"]
  end

  test "delete_episode deletes existing episode and enqueues job" do
    initialize_session!

    episode = @user.episodes.first
    skip "No fixtures for user one's episodes" unless episode

    assert_enqueued_with(job: DeleteEpisodeJob) do
      post "/mcp",
        params: jsonrpc_tool_call("delete_episode", { id: episode.prefix_id }),
        headers: mcp_headers(token: @token.token)
    end

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal true, data["deleted"]
  end

  # --- Auth edge cases ---

  test "returns 401 when resource owner cannot be found" do
    # Verify that User.find_by returning nil produces a 401, not a 500.
    # This guards against orphaned tokens (user deleted without revoking tokens).
    original_find_by = User.method(:find_by)
    User.define_singleton_method(:find_by) { |**_args| nil }

    begin
      post "/mcp",
        params: jsonrpc_request("initialize"),
        headers: mcp_headers(token: @token.token)
      assert_response :unauthorized
    ensure
      User.define_singleton_method(:find_by, original_find_by)
    end
  end

  # --- Cross-user isolation ---

  test "user cannot see another user's episodes" do
    initialize_session!

    other_user = users(:two)
    other_episode = other_user.episodes.first
    skip "No fixtures for user two's episodes" unless other_episode

    post "/mcp",
      params: jsonrpc_tool_call("get_episode", { id: other_episode.prefix_id }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "not_found", data["error"]
  end

  # --- Tier limit / rate limit / voice validation ---

  test "create_episode_from_url returns tier limit error" do
    initialize_session!

    # Exhaust free tier by creating enough episode usage records
    usage = EpisodeUsage.current_for(@user)
    usage.update!(episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES)

    post "/mcp",
      params: jsonrpc_tool_call("create_episode_from_url", { url: "https://example.com/article" }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "tier_limit", data["error"]
    assert_match "upgrade", data["message"].downcase
  end

  test "create_episode_from_text returns tier limit error" do
    initialize_session!

    usage = EpisodeUsage.current_for(@user)
    usage.update!(episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES)

    post "/mcp",
      params: jsonrpc_tool_call("create_episode_from_text", {
        text: "Some text " * 20,
        title: "Test"
      }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "tier_limit", data["error"]
  end

  test "create_episode_from_url returns rate limit error" do
    initialize_session!

    # Create episodes to exhaust hourly rate limit
    ChecksEpisodeRateLimit::HOURLY_LIMIT.times do |i|
      @user.episodes.create!(
        podcast: @user.podcasts.first,
        title: "Rate limit test #{i}",
        author: "Test",
        description: "Rate limit test episode",
        source_type: "url",
        source_url: "https://example.com",
        status: "pending"
      )
    end

    post "/mcp",
      params: jsonrpc_tool_call("create_episode_from_url", { url: "https://example.com/article" }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "rate_limited", data["error"]
  end

  test "create_episode_from_url returns invalid voice error" do
    initialize_session!

    post "/mcp",
      params: jsonrpc_tool_call("create_episode_from_url", { url: "https://example.com/article", voice: "nonexistent_voice" }),
      headers: mcp_headers(token: @token.token)

    assert_response :success
    result = parse_tool_result
    data = JSON.parse(result)
    assert_equal "invalid_voice", data["error"]
    assert_match "list_voices", data["message"]
  end

  private

  def jsonrpc_request(method, params = nil)
    body = { jsonrpc: "2.0", id: 1, method: method }
    body[:params] = params if params
    body.to_json
  end

  def jsonrpc_tool_call(tool_name, arguments = {})
    jsonrpc_request("tools/call", { name: tool_name, arguments: arguments })
  end

  def mcp_headers(token: nil)
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }
    headers["Authorization"] = "Bearer #{token}" if token
    headers
  end

  def initialize_session!
    post "/mcp",
      params: jsonrpc_request("initialize", { protocolVersion: "2025-11-25", capabilities: {} }),
      headers: mcp_headers(token: @token.token)
    assert_response :success
  end

  def parse_jsonrpc_result
    JSON.parse(response.body)["result"]
  end

  def parse_tool_result
    result = parse_jsonrpc_result
    result["content"].first["text"]
  end
end
