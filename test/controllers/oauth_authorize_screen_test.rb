# frozen_string_literal: true

require "test_helper"

class OAuthAuthorizeScreenTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = Doorkeeper::Application.create!(
      name: "Claude",
      uid: "test_claude",
      redirect_uri: "http://localhost:3001/callback",
      scopes: "podread",
      confidential: false
    )
  end

  test "authorize screen shows app name and permissions" do
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

    assert_response :success
    assert_match "Claude", response.body
    assert_match "wants to access your PodRead account", response.body
    assert_match "Create podcast episodes from articles and text", response.body
    assert_match "View your episodes and feed", response.body
    assert_match "Check your account status", response.body
    assert_match @user.email, response.body
  end

  test "authorize screen shows Allow and Deny buttons" do
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

    assert_response :success
    assert_match "Allow", response.body
    assert_match "Deny", response.body
  end

  test "deny returns error to client" do
    sign_in_as @user

    code_verifier = SecureRandom.hex(32)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    delete "/oauth/authorize", params: {
      client_id: @app.uid,
      redirect_uri: @app.redirect_uri,
      response_type: "code",
      scope: "podread",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    assert_response :redirect
    redirect = URI.parse(response.location)
    params = Rack::Utils.parse_query(redirect.query)
    assert_equal "access_denied", params["error"]
  end
end
