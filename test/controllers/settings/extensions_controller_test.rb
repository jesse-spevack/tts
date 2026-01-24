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
end
