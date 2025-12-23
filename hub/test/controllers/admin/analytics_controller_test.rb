require "test_helper"

class Admin::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @regular_user = users(:one)
  end

  test "redirects unauthenticated users to root" do
    get admin_analytics_url
    assert_redirected_to root_url
  end

  test "returns not found for non-admin users" do
    token = GenerateAuthToken.call(user: @regular_user)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :not_found
  end

  test "allows admin users to view analytics" do
    token = GenerateAuthToken.call(user: @admin)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :success
  end

  test "displays page view counts" do
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "def", user_agent: "test")
    PageView.create!(path: "/how-it-sounds", visitor_hash: "abc", user_agent: "test")

    token = GenerateAuthToken.call(user: @admin)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :success
    assert_select "td", text: "3" # total views
  end

  test "displays unique visitor count" do
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "def", user_agent: "test")

    token = GenerateAuthToken.call(user: @admin)
    get auth_url, params: { token: token }

    get admin_analytics_url
    assert_response :success
    assert_select "td", text: "2" # unique visitors
  end
end
