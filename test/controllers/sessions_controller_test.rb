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
    token = GeneratesAuthToken.call(user: @user)

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
    token = GeneratesAuthToken.call(user: @user)
    get auth_url, params: { token: token }

    delete session_url
    assert_redirected_to root_url
    assert_empty cookies[:session_id].to_s
  end

  test "verify with premium_monthly plan redirects to checkout without flash" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "premium_monthly" }

    assert_redirected_to checkout_path(price_id: AppConfig::Stripe::PRICE_ID_MONTHLY)
    assert_nil flash[:notice], "Should not show 'Welcome back!' flash when redirecting to checkout"
  end

  test "verify with premium_annual plan redirects to checkout without flash" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "premium_annual" }

    assert_redirected_to checkout_path(price_id: AppConfig::Stripe::PRICE_ID_ANNUAL)
    assert_nil flash[:notice], "Should not show 'Welcome back!' flash when redirecting to checkout"
  end

  test "verify with credit_pack plan redirects to checkout without flash" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "credit_pack" }

    assert_redirected_to checkout_path(price_id: AppConfig::Stripe::PRICE_ID_CREDIT_PACK)
    assert_nil flash[:notice], "Should not show 'Welcome back!' flash when redirecting to checkout"
  end

  test "verify without plan redirects to episodes" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token }

    assert_redirected_to new_episode_path
  end

  test "all checkout price IDs have a corresponding plan redirect" do
    # Map every PRICE_ID_* constant to its plan name
    plan_names = {
      AppConfig::Stripe::PRICE_ID_MONTHLY => "premium_monthly",
      AppConfig::Stripe::PRICE_ID_ANNUAL => "premium_annual",
      AppConfig::Stripe::PRICE_ID_CREDIT_PACK => "credit_pack"
    }

    # If a new PRICE_ID_* constant is added to AppConfig::Stripe, this test
    # will fail until its plan redirect is added to SessionsController
    stripe_price_constants = AppConfig::Stripe.constants.select { |c| c.to_s.start_with?("PRICE_ID_") }
    mapped_price_ids = plan_names.keys

    stripe_price_constants.each do |const|
      price_id = AppConfig::Stripe.const_get(const)
      assert_includes mapped_price_ids, price_id,
        "AppConfig::Stripe::#{const} (#{price_id}) has no plan mapping in this test — " \
        "add it to plan_names and ensure SessionsController#post_login_path handles it"
    end

    # Verify each plan actually redirects to checkout
    plan_names.each do |price_id, plan|
      # Log out so the authenticated? guard doesn't short-circuit
      delete session_url if cookies[:session_id].present?

      token = GeneratesAuthToken.call(user: @user)
      get auth_url, params: { token: token, plan: plan }
      assert_redirected_to checkout_path(price_id: price_id),
        "Plan '#{plan}' should redirect to checkout with price_id=#{price_id}"
    end
  end

  test "create passes plan param to magic link" do
    assert_emails 1 do
      post session_url, params: { email_address: "test@example.com", plan: "premium_monthly" }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.body.to_s, "plan=premium_monthly"
  end

  # Defense in depth around the soft-delete revive flow: SendsMagicLink
  # intentionally reaches soft-deleted users so they can restore. That makes
  # an attacker who knows the deleted email able to spam mail to it. Per-email
  # rate-limit applied to ALL users (not just soft-deleted) is the orthogonal
  # mitigation. Limiter is wired through RateLimitStore for testability — see
  # the comment on SessionsController::MagicLinkRateLimitStore.
  test "magic-link rate limit: 6th request within an hour for the same email is rejected" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    5.times do
      post session_url, params: { email_address: "spammed@example.com" }
      assert_redirected_to root_url
    end

    assert_no_emails do
      post session_url, params: { email_address: "spammed@example.com" }
    end
    assert_redirected_to root_url
    assert_match(/wait/i, flash[:alert].to_s)
  ensure
    Rails.cache = original_cache if original_cache
  end

  test "magic-link rate limit: different emails are independently limited" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    5.times do
      post session_url, params: { email_address: "alice@example.com" }
    end

    assert_emails 1 do
      post session_url, params: { email_address: "bob@example.com" }
    end
    assert_redirected_to root_url
    assert_equal "Check your email for a login link!", flash[:notice]
  ensure
    Rails.cache = original_cache if original_cache
  end

  test "magic-link rate limit: case- and whitespace-insensitive on email" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    5.times { post session_url, params: { email_address: "Mixed@Example.com" } }

    assert_no_emails do
      post session_url, params: { email_address: "  mixed@example.com  " }
    end
    assert_redirected_to root_url
  ensure
    Rails.cache = original_cache if original_cache
  end
end
