# frozen_string_literal: true

require "test_helper"

class OAuthMcpIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = Doorkeeper::Application.create!(
      name: "Integration Test Client",
      uid: "integration_test",
      redirect_uri: "http://localhost:3001/callback",
      scopes: "podread",
      confidential: false
    )
  end

  test "full flow: OAuth authorize -> token exchange -> MCP initialize -> tool call" do
    sign_in_as @user

    # 1. OAuth authorization code request with PKCE
    code_verifier = SecureRandom.hex(32)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    get "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }
    assert_response :success
    assert_match "wants to access your PodRead account", response.body

    # 2. User approves
    post "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }
    assert_response :redirect
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
    assert code.present?

    # 3. Exchange code for tokens
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      code_verifier: code_verifier
    }
    assert_response :success
    tokens = JSON.parse(response.body)
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]
    assert access_token.present?
    assert refresh_token.present?

    # 4. MCP initialize
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize",
                params: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
      headers: mcp_headers(access_token)
    assert_response :success
    result = JSON.parse(response.body)["result"]
    assert_equal "podread", result["serverInfo"]["name"]

    # 5. MCP tools/list
    post "/mcp",
      params: { jsonrpc: "2.0", id: 2, method: "tools/list" }.to_json,
      headers: mcp_headers(access_token)
    assert_response :success
    tools = JSON.parse(response.body)["result"]["tools"]
    assert_equal 7, tools.size

    # 6. MCP tool call: list_voices
    post "/mcp",
      params: { jsonrpc: "2.0", id: 3, method: "tools/call",
                params: { name: "list_voices", arguments: {} } }.to_json,
      headers: mcp_headers(access_token)
    assert_response :success
    voices_result = JSON.parse(response.body)["result"]["content"].first["text"]
    voices = JSON.parse(voices_result)
    assert voices["voices"].is_a?(Array)
    assert voices["voices"].any?

    # 7. MCP tool call: get_feed_url
    post "/mcp",
      params: { jsonrpc: "2.0", id: 4, method: "tools/call",
                params: { name: "get_feed_url", arguments: {} } }.to_json,
      headers: mcp_headers(access_token)
    assert_response :success
    feed_result = JSON.parse(response.body)["result"]["content"].first["text"]
    feed = JSON.parse(feed_result)
    assert feed["feed_url"].present?

    # 8. MCP tool call: list_episodes
    post "/mcp",
      params: { jsonrpc: "2.0", id: 5, method: "tools/call",
                params: { name: "list_episodes", arguments: { page: 1, limit: 5 } } }.to_json,
      headers: mcp_headers(access_token)
    assert_response :success
    episodes_result = JSON.parse(response.body)["result"]["content"].first["text"]
    episodes = JSON.parse(episodes_result)
    assert episodes["episodes"].is_a?(Array)
    assert episodes["meta"]["total"].is_a?(Integer)
  end

  test "MCP rejects requests after token is revoked" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    # Works initially
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize",
                params: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
      headers: mcp_headers(token.token)
    assert_response :success

    # Revoke the token
    token.revoke

    # Fails after revocation
    post "/mcp",
      params: { jsonrpc: "2.0", id: 2, method: "tools/list" }.to_json,
      headers: mcp_headers(token.token)
    assert_response :unauthorized
  end

  test "MCP rejects requests after token expires" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 0,
      created_at: 2.hours.ago
    )

    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize",
                params: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
      headers: mcp_headers(token.token)
    assert_response :unauthorized
  end

  test "token refresh provides continued MCP access" do
    sign_in_as @user

    code_verifier = SecureRandom.hex(32)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    # Get authorization code
    get "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }
    post "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    # Exchange for tokens
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      code_verifier: code_verifier
    }
    original_tokens = JSON.parse(response.body)

    # Refresh the token
    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: original_tokens["refresh_token"],
      client_id: @app.uid
    }
    assert_response :success
    new_tokens = JSON.parse(response.body)
    assert_not_equal original_tokens["access_token"], new_tokens["access_token"]

    # Use the new token for MCP
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize",
                params: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
      headers: mcp_headers(new_tokens["access_token"])
    assert_response :success
  end

  test "well-known endpoints support OAuth discovery" do
    # Protected resource metadata points to authorization server
    get "/.well-known/oauth-protected-resource"
    assert_response :success
    resource = JSON.parse(response.body)
    assert resource["authorization_servers"].present?

    # Authorization server metadata describes capabilities
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    server_meta = JSON.parse(response.body)
    assert_equal "https://example.com/oauth/authorize", server_meta["authorization_endpoint"]
    assert_equal "https://example.com/oauth/token", server_meta["token_endpoint"]
    assert_includes server_meta["code_challenge_methods_supported"], "S256"
    assert_includes server_meta["grant_types_supported"], "authorization_code"
    assert_includes server_meta["grant_types_supported"], "refresh_token"
  end

  test "settings page shows connected app after OAuth authorization" do
    sign_in_as @user

    # Create an active token
    Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    get settings_path
    assert_response :success
    assert_match "Integration Test Client", response.body
    assert_match "Disconnect", response.body
  end

  test "disconnecting from settings revokes OAuth tokens and blocks MCP" do
    sign_in_as @user

    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    # MCP works
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize",
                params: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
      headers: mcp_headers(token.token)
    assert_response :success

    # Disconnect via settings
    delete settings_connected_app_path(@app)
    assert_redirected_to settings_path

    # MCP no longer works
    post "/mcp",
      params: { jsonrpc: "2.0", id: 2, method: "tools/list" }.to_json,
      headers: mcp_headers(token.token)
    assert_response :unauthorized
  end

  private

  def mcp_headers(token)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "Authorization" => "Bearer #{token}"
    }
  end
end
