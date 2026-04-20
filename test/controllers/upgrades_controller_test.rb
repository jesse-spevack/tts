require "test_helper"

# After iny7 the /upgrade page disappears — UpgradesController#show becomes
# a plain redirect to /billing for any authenticated user. Anonymous users
# still get bounced through login first.
class UpgradesControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  test "show requires authentication" do
    get upgrade_path
    assert_redirected_to login_path(return_to: "/upgrade")
  end

  test "show redirects free user to billing (no longer renders /upgrade)" do
    sign_in_as(users(:free_user))
    get upgrade_path
    assert_redirected_to billing_path
  end

  test "show redirects subscriber to billing" do
    sign_in_as(users(:subscriber))
    get upgrade_path
    assert_redirected_to billing_path
  end

  test "show redirects credit user to billing" do
    sign_in_as(users(:credit_user))
    get upgrade_path
    assert_redirected_to billing_path
  end

  test "show redirects complimentary user to billing" do
    sign_in_as(users(:complimentary_user))
    get upgrade_path
    assert_redirected_to billing_path
  end

  test "show redirects unlimited user to billing" do
    sign_in_as(users(:unlimited_user))
    get upgrade_path
    assert_redirected_to billing_path
  end
end
