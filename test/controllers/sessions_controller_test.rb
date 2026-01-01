require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get new" do
    get root_url
    assert_response :success
  end

  test "create sends magic link email" do
    assert_emails 1 do
      post session_url, params: { email_address: "test@example.com" }
    end
    assert_redirected_to root_url
    assert_equal "Check your email for a login link!", flash[:notice]
  end

  test "create with token authenticates user" do
    token = GenerateAuthToken.call(user: @user)

    get auth_url, params: { token: token }

    assert_redirected_to new_episode_url
    assert_equal "Welcome back!", flash[:notice]
    assert cookies[:session_id].present?
  end

  test "create with invalid token redirects to login" do
    get auth_url, params: { token: "invalid" }

    assert_redirected_to root_url
    assert_equal "Invalid or expired login link. Please try again.", flash[:alert]
  end

  test "should destroy session" do
    token = GenerateAuthToken.call(user: @user)
    get auth_url, params: { token: token }

    delete session_url
    assert_redirected_to root_url
    assert_empty cookies[:session_id].to_s
  end

  test "verify with premium_monthly plan redirects to checkout" do
    token = GenerateAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "premium_monthly" }

    assert_redirected_to checkout_path(price_id: AppConfig::Stripe::PRICE_ID_MONTHLY)
  end

  test "verify with premium_annual plan redirects to checkout" do
    token = GenerateAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "premium_annual" }

    assert_redirected_to checkout_path(price_id: AppConfig::Stripe::PRICE_ID_ANNUAL)
  end

  test "verify without plan redirects to episodes" do
    token = GenerateAuthToken.call(user: @user)

    get auth_url, params: { token: token }

    assert_redirected_to new_episode_path
  end

  test "create passes plan param to magic link" do
    assert_emails 1 do
      post session_url, params: { email_address: "test@example.com", plan: "premium_monthly" }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.body.to_s, "plan=premium_monthly"
  end
end
