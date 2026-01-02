require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  test "show requires authentication" do
    get billing_path
    assert_redirected_to root_path
  end

  test "show renders for free user" do
    sign_in_as(users(:free_user))
    get billing_path
    assert_response :success
  end

  test "show renders for premium user" do
    sign_in_as(users(:subscriber))
    get billing_path
    assert_response :success
  end
end
