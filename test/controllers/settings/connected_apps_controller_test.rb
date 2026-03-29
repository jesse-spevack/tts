# frozen_string_literal: true

require "test_helper"

class Settings::ConnectedAppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @app = Doorkeeper::Application.create!(
      name: "Claude",
      uid: "test_claude_settings",
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

  test "settings page shows connected apps section" do
    get settings_path
    assert_response :success
    assert_match "Connected Apps", response.body
    assert_match "Claude", response.body
  end

  test "settings page shows no apps message when none connected" do
    @token.revoke
    get settings_path
    assert_response :success
    assert_match "No apps connected", response.body
  end

  test "disconnect revokes all tokens for the app" do
    delete settings_connected_app_path(@app)
    assert_redirected_to settings_path
    follow_redirect!
    assert_match "Claude has been disconnected", response.body

    assert @token.reload.revoked?
  end

  test "disconnect with nonexistent app shows error" do
    delete settings_connected_app_path(id: 99999)
    assert_redirected_to settings_path
    follow_redirect!
    assert_match "App not found", response.body
  end
end
