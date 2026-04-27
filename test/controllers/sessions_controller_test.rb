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

  # --- Premium plans are no longer a checkout flow (iny7 + winddown) ---
  # iny7 deleted the public subscription signup surfaces; agent-team-9rt7
  # finished the winddown by deleting the subscription code entirely.
  # `premium_monthly` and `premium_annual` are no longer valid `plan` values
  # for the magic-link round-trip: post-login redirect must fall through to
  # after_authentication_url (new_episode_path). A stale pre-iny7 link
  # shouldn't route users into a dead premium checkout.

  test "verify with premium_monthly plan does NOT redirect to subscription checkout" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "premium_monthly" }

    assert_redirected_to new_episode_path
    refute_match(/price_id=/, @response.redirect_url,
      "premium_monthly must not redirect into a subscription checkout after iny7")
  end

  test "verify with premium_annual plan does NOT redirect to subscription checkout" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "premium_annual" }

    assert_redirected_to new_episode_path
    refute_match(/price_id=/, @response.redirect_url,
      "premium_annual must not redirect into a subscription checkout after iny7")
  end

  # --- Credit pack plan + pack_size carry (iny7 LOAD-BEARING design) ---

  test "verify with credit_pack + pack_size=5 redirects to Starter checkout" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "credit_pack", pack_size: 5 }

    assert_redirected_to checkout_path(pack_size: 5)
    assert_nil flash[:notice], "No welcome flash when heading into checkout"
  end

  test "verify with credit_pack + pack_size=10 redirects to Standard checkout" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "credit_pack", pack_size: 10 }

    assert_redirected_to checkout_path(pack_size: 10)
    assert_nil flash[:notice]
  end

  test "verify with credit_pack + pack_size=20 redirects to Bulk checkout" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "credit_pack", pack_size: 20 }

    assert_redirected_to checkout_path(pack_size: 20)
    assert_nil flash[:notice]
  end

  test "verify with credit_pack but no pack_size falls back to Starter" do
    # A pre-iny7 signup session may have set plan=credit_pack without a
    # pack_size. Per design, the fallback is the first PACKS entry (Starter).
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "credit_pack" }

    assert_redirected_to checkout_path(pack_size: AppConfig::Credits::PACKS.first[:size])
  end

  test "verify with credit_pack + bogus pack_size falls back to Starter" do
    # Tampered / out-of-catalog pack_size must not round-trip. presence_in
    # the PACKS catalog, else fall back to Starter.
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token, plan: "credit_pack", pack_size: 99 }

    assert_redirected_to checkout_path(pack_size: AppConfig::Credits::PACKS.first[:size])
  end

  test "pack_size does not leak across sessions" do
    # Sign in with pack_size=10 for credit_pack.
    token_a = GeneratesAuthToken.call(user: @user)
    get auth_url, params: { token: token_a, plan: "credit_pack", pack_size: 10 }
    assert_redirected_to checkout_path(pack_size: 10)

    # Log out, then back in with no plan / no pack_size.
    delete session_url
    other_user = users(:two)
    token_b = GeneratesAuthToken.call(user: other_user)
    get auth_url, params: { token: token_b }

    # Lands on the default post-login destination, NOT a checkout.
    assert_redirected_to new_episode_path
  end

  test "verify without plan redirects to episodes" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token }

    assert_redirected_to new_episode_path
  end

  # --- Plan/pack_size parameterized handler coverage (iny7) ---
  # Pre-iny7 this was a parametric check over PRICE_ID_* constants. After
  # iny7, premium price IDs no longer have a plan handler; the only
  # plan-routed checkout path is credit_pack, parameterized by pack_size
  # across the three PACKS entries.

  test "every Credits::PACKS entry has a credit_pack plan handler" do
    AppConfig::Credits::PACKS.each do |pack|
      delete session_url if cookies[:session_id].present?

      token = GeneratesAuthToken.call(user: @user)
      get auth_url, params: { token: token, plan: "credit_pack", pack_size: pack[:size] }

      assert_redirected_to checkout_path(pack_size: pack[:size]),
        "credit_pack with pack_size=#{pack[:size]} (#{pack[:label]}) must redirect to its checkout"
    end
  end

  test "premium price IDs are NOT mapped to plan handlers after iny7" do
    # The previous parametric test required every PRICE_ID_* constant in
    # AppConfig::Stripe to have a plan handler. iny7 + the winddown delete
    # the premium plan handlers. This assertion inverts the expectation: a
    # user arriving at auth with plan=premium_* must land on the default
    # post-login destination (new_episode_path), NOT a Stripe checkout with
    # any price_id.
    %w[premium_monthly premium_annual].each do |plan|
      delete session_url if cookies[:session_id].present?

      token = GeneratesAuthToken.call(user: @user)
      get auth_url, params: { token: token, plan: plan }

      assert_redirected_to new_episode_path,
        "Plan '#{plan}' must redirect to the default post-login destination"
      refute_match(/price_id=/, @response.redirect_url,
        "Plan '#{plan}' must not redirect to a Stripe checkout")
    end
  end

  # --- Magic link params ---

  test "create passes plan param to magic link" do
    assert_emails 1 do
      post session_url, params: { email_address: "test@example.com", plan: "credit_pack" }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.body.to_s, "plan=credit_pack"
  end

  test "create passes pack_size param to magic link" do
    assert_emails 1 do
      post session_url, params: {
        email_address: "test@example.com",
        plan: "credit_pack",
        pack_size: "10"
      }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.body.to_s, "pack_size=10"
  end
end
