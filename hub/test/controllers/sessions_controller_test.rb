require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "create sends magic link email" do
    assert_emails 1 do
      post session_url, params: { email_address: "test@example.com" }
    end
    assert_redirected_to new_session_url
    assert_equal "Check your email for a login link!", flash[:notice]
  end

  test "create with token authenticates user" do
    GenerateAuthToken.call(user: @user)

    get new_session_url, params: { token: @user.auth_token }

    assert_redirected_to root_url
    assert_equal "Welcome back!", flash[:notice]
    assert cookies[:session_id].present?
  end

  test "create with invalid token redirects to login" do
    get new_session_url, params: { token: "invalid" }

    assert_redirected_to new_session_url
    assert_equal "Invalid or expired login link. Please try again.", flash[:alert]
  end

  test "should destroy session" do
    GenerateAuthToken.call(user: @user)
    get new_session_url, params: { token: @user.auth_token }

    delete session_url
    assert_redirected_to new_session_url
    assert_empty cookies[:session_id]
  end
end
