# frozen_string_literal: true

require "test_helper"

class WellKnownControllerTest < ActionDispatch::IntegrationTest
  test "GET /.well-known/oauth-protected-resource returns RFC 9728 metadata" do
    get "/.well-known/oauth-protected-resource"

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "https://example.com", json["resource"]
    assert_equal [ "https://example.com" ], json["authorization_servers"]
    assert_equal [ "podread" ], json["scopes_supported"]
    assert_equal [ "header" ], json["bearer_methods_supported"]
  end

  test "GET /.well-known/oauth-authorization-server returns RFC 8414 metadata" do
    get "/.well-known/oauth-authorization-server"

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "https://example.com", json["issuer"]
    assert_equal "https://example.com/oauth/authorize", json["authorization_endpoint"]
    assert_equal "https://example.com/oauth/token", json["token_endpoint"]
    assert_equal "https://example.com/oauth/revoke", json["revocation_endpoint"]
    assert_equal "https://example.com/oauth/introspect", json["introspection_endpoint"]
    assert_equal [ "podread" ], json["scopes_supported"]
    assert_equal [ "code" ], json["response_types_supported"]
    assert_equal [ "authorization_code", "refresh_token" ], json["grant_types_supported"]
    assert_equal [ "none" ], json["token_endpoint_auth_methods_supported"]
    assert_equal [ "S256" ], json["code_challenge_methods_supported"]
    assert_equal "https://example.com/help/claude", json["service_documentation"]
  end

  test "well-known endpoints are accessible without authentication" do
    # These must work for unauthenticated MCP clients discovering OAuth config
    get "/.well-known/oauth-protected-resource"
    assert_response :success

    get "/.well-known/oauth-authorization-server"
    assert_response :success
  end

  test "well-known endpoints return JSON content type" do
    get "/.well-known/oauth-protected-resource"
    assert_match %r{application/json}, response.content_type

    get "/.well-known/oauth-authorization-server"
    assert_match %r{application/json}, response.content_type
  end
end
