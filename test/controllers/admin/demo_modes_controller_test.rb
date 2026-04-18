require "test_helper"

class Admin::DemoModesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @regular_user = users(:one)
  end

  test "redirects unauthenticated users to root" do
    post admin_demo_mode_url
    assert_redirected_to root_url
  end

  test "returns not found for non-admin users" do
    sign_in_as @regular_user

    post admin_demo_mode_url
    assert_response :not_found
  end

  test "admin toggles session[:demo_mode] from nil/false to true" do
    sign_in_as @admin

    post admin_demo_mode_url
    assert_response :redirect
    assert_equal true, session[:demo_mode]
  end

  test "admin toggles session[:demo_mode] from true back to false" do
    sign_in_as @admin

    # First toggle: off -> on
    post admin_demo_mode_url
    assert_equal true, session[:demo_mode]

    # Second toggle: on -> off
    post admin_demo_mode_url
    assert_equal false, session[:demo_mode]
  end

  test "admin toggle redirects back to referrer when present" do
    sign_in_as @admin

    post admin_demo_mode_url, headers: { "HTTP_REFERER" => episodes_url }
    assert_redirected_to episodes_url
  end

  test "admin toggle falls back to root when no referrer" do
    sign_in_as @admin

    post admin_demo_mode_url
    assert_redirected_to root_url
  end
end
