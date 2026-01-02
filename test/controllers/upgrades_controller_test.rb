require "test_helper"

class UpgradesControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  test "show requires authentication" do
    get upgrade_path
    assert_redirected_to root_path
  end

  test "show renders for free user" do
    sign_in_as(users(:free_user))
    get upgrade_path
    assert_response :success
  end

  test "show redirects premium user to billing" do
    sign_in_as(users(:subscriber))
    get upgrade_path
    assert_redirected_to billing_path
  end
end
