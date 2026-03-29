# frozen_string_literal: true

require "test_helper"

class OAuthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = Doorkeeper::Application.create!(
      name: "Test App",
      uid: "test_client",
      redirect_uri: "http://localhost:3001/callback",
      scopes: "podread",
      confidential: false
    )
  end

  # --- Doorkeeper configuration tests ---

  test "doorkeeper is configured for authorization_code only" do
    assert_equal %w[authorization_code], Doorkeeper.config.grant_flows
  end

  test "doorkeeper requires PKCE for public clients" do
    assert Doorkeeper.config.force_pkce?
  end

  test "doorkeeper uses S256 only for PKCE" do
    assert_equal %w[S256], Doorkeeper.config.pkce_code_challenge_methods
  end

  test "access tokens expire in 1 hour" do
    assert_equal 1.hour.to_i, Doorkeeper.config.access_token_expires_in
  end

  test "refresh tokens are enabled" do
    assert Doorkeeper.config.refresh_token_enabled?
  end

  test "default scope is podread" do
    assert_equal Doorkeeper::OAuth::Scopes.from_string("podread"), Doorkeeper.config.default_scopes
  end

  # --- OAuth flow tests ---

  test "authorize redirects to login when not authenticated" do
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

    assert_response :redirect
    assert_match %r{/login}, response.location
  end

  test "full OAuth authorization code flow with PKCE" do
    sign_in_as @user

    code_verifier = SecureRandom.hex(32)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    # Step 1: GET /oauth/authorize — renders the authorization form
    get "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    assert_response :success

    # Step 2: POST /oauth/authorize — user approves
    post "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    assert_response :redirect
    redirect = URI.parse(response.location)
    code = Rack::Utils.parse_query(redirect.query)["code"]
    assert code.present?, "Expected authorization code in redirect"

    # Step 3: POST /oauth/token — exchange code for tokens
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      code_verifier: code_verifier
    }

    assert_response :success
    token_response = JSON.parse(response.body)
    assert token_response["access_token"].present?
    assert token_response["refresh_token"].present?
    assert_equal "podread", token_response["scope"]
    assert_equal 3600, token_response["expires_in"]
    assert_equal "Bearer", token_response["token_type"]
  end

  test "token exchange fails without PKCE code_verifier" do
    sign_in_as @user

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

    post "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    redirect = URI.parse(response.location)
    code = Rack::Utils.parse_query(redirect.query)["code"]

    # Try to exchange without code_verifier — should fail
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri
    }

    assert_response :bad_request
  end

  test "refresh token rotation issues new access and refresh tokens" do
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

    redirect = URI.parse(response.location)
    code = Rack::Utils.parse_query(redirect.query)["code"]

    # Exchange for tokens
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      code_verifier: code_verifier
    }

    original = JSON.parse(response.body)

    # Refresh the token
    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: original["refresh_token"],
      client_id: @app.uid
    }

    assert_response :success
    refreshed = JSON.parse(response.body)
    assert refreshed["access_token"].present?
    assert refreshed["refresh_token"].present?
    assert_not_equal original["access_token"], refreshed["access_token"]
    assert_not_equal original["refresh_token"], refreshed["refresh_token"]
  end

  test "revoke endpoint invalidates access token" do
    # Create a token directly
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    post "/oauth/revoke", params: {
      token: token.token,
      client_id: @app.uid
    }

    assert_response :success
    assert token.reload.revoked?
  end

  test "user has_many oauth_access_tokens" do
    token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    assert_includes @user.oauth_access_tokens, token
  end
end
