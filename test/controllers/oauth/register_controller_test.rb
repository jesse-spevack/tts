# frozen_string_literal: true

require "test_helper"

class Oauth::RegisterControllerTest < ActionDispatch::IntegrationTest
  test "registers a new OAuth client" do
    assert_difference "Doorkeeper::Application.count", 1 do
      post "/oauth/register",
        params: {
          redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ],
          client_name: "Claude"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body["client_id"].present?
    assert_equal "Claude", body["client_name"]
    assert_equal [ "https://claude.ai/api/mcp/auth_callback" ], body["redirect_uris"]
    assert_equal "none", body["token_endpoint_auth_method"]
    assert_equal [ "authorization_code" ], body["grant_types"]
    assert_equal [ "code" ], body["response_types"]
    assert body["client_id_issued_at"].is_a?(Integer)
    assert_equal 0, body["client_secret_expires_at"]
  end

  test "registers with multiple redirect URIs" do
    post "/oauth/register",
      params: {
        redirect_uris: [
          "https://claude.ai/api/mcp/auth_callback",
          "https://claude.com/api/mcp/auth_callback"
        ],
        client_name: "Claude"
      }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 2, body["redirect_uris"].length
  end

  test "uses default name when client_name not provided" do
    post "/oauth/register",
      params: {
        redirect_uris: [ "https://example.com/callback" ]
      }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "MCP Client", body["client_name"]
  end

  test "returns error when redirect_uris missing" do
    post "/oauth/register",
      params: {}.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_client_metadata", body["error"]
    assert_match "redirect_uris", body["error_description"]
  end

  test "returns error when redirect_uris is not an array" do
    post "/oauth/register",
      params: { redirect_uris: "https://example.com/callback" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_client_metadata", body["error"]
  end

  test "created application is non-confidential" do
    post "/oauth/register",
      params: {
        redirect_uris: [ "https://example.com/callback" ],
        client_name: "Test"
      }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    body = JSON.parse(response.body)
    app = Doorkeeper::Application.find_by(uid: body["client_id"])
    assert_not app.confidential
  end
end
