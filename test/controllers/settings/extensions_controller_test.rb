require "test_helper"

class Settings::ExtensionsControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  test "show requires authentication" do
    get settings_extensions_path
    assert_redirected_to root_path
  end

  test "show renders for authenticated user" do
    sign_in_as(users(:free_user))
    get settings_extensions_path
    assert_response :success
  end

  test "show displays not connected state when no token exists" do
    sign_in_as(users(:free_user))
    get settings_extensions_path
    assert_response :success
    assert_match "Not connected", response.body
  end

  test "show displays connected state when active token exists" do
    sign_in_as(users(:one))
    get settings_extensions_path
    assert_response :success
    assert_match "Connected", response.body
    assert_match "tts_ext_a...", response.body
  end

  test "show displays last used time when token has been used" do
    sign_in_as(users(:two))
    get settings_extensions_path
    assert_response :success
    assert_match "ago", response.body
  end

  test "show displays Never when token has not been used" do
    sign_in_as(users(:one))
    get settings_extensions_path
    assert_response :success
    assert_match "Never", response.body
  end

  test "show displays disconnect button when connected" do
    sign_in_as(users(:one))
    get settings_extensions_path
    assert_response :success
    assert_match "Disconnect Extension", response.body
  end

  test "destroy requires authentication" do
    delete settings_extensions_path
    assert_redirected_to root_path
  end

  test "destroy revokes active token and redirects with success notice" do
    user = users(:one)
    sign_in_as(user)
    token = api_tokens(:active_token)
    assert token.active?

    delete settings_extensions_path

    assert_redirected_to settings_extensions_path
    follow_redirect!
    assert_match "Extension disconnected successfully", response.body

    token.reload
    assert token.revoked?
  end

  test "destroy redirects with alert when no active token exists" do
    user = users(:free_user)
    sign_in_as(user)
    assert_nil ApiToken.active_token_for(user)

    delete settings_extensions_path

    assert_redirected_to settings_extensions_path
    follow_redirect!
    assert_match "No active extension connection found", response.body
  end
end
