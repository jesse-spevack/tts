require "test_helper"

class Admin::MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @regular_user = users(:one)
  end

  test "redirects unauthenticated users to login" do
    get admin_metrics_url
    assert_redirected_to login_path(return_to: "/admin/metrics")
  end

  test "returns not found for non-admin users" do
    sign_in_as @regular_user

    get admin_metrics_url
    assert_response :not_found
  end

  test "allows admin users to view metrics" do
    sign_in_as @admin

    get admin_metrics_url
    assert_response :success
  end

  test "renders activation card" do
    sign_in_as @admin

    get admin_metrics_url
    assert_response :success
    assert_select "h2", text: /Activation/
  end

  test "renders cohort retention card" do
    sign_in_as @admin

    get admin_metrics_url
    assert_response :success
    assert_select "h2", text: /Cohort Retention/
  end

  test "renders WAU card" do
    sign_in_as @admin

    get admin_metrics_url
    assert_response :success
    assert_select "h2", text: /Weekly Active Users/
  end

  test "renders failure rate card" do
    sign_in_as @admin

    get admin_metrics_url
    assert_response :success
    assert_select "h2", text: /Failure Rate/
  end
end
