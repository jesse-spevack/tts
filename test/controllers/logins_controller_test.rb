require "test_helper"

class LoginsControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  setup do
    @user = users(:one)
  end

  test "new renders login page for unauthenticated user" do
    get login_path

    assert_response :success
  end

  test "new redirects to new_episode_path when authenticated without return_to" do
    sign_in_as(@user)

    get login_path

    assert_redirected_to new_episode_path
  end

  test "new redirects to return_to when authenticated with return_to param" do
    sign_in_as(@user)

    get login_path(return_to: extension_connect_path)

    assert_redirected_to extension_connect_path
  end

  test "new stores return_to for unauthenticated user" do
    get login_path(return_to: "/some/path")

    assert_response :success
    assert_match "/some/path", response.body
  end

  test "new ignores blank return_to when authenticated" do
    sign_in_as(@user)

    get login_path(return_to: "")

    assert_redirected_to new_episode_path
  end
end
