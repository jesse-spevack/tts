# frozen_string_literal: true

require "test_helper"

class MarketingAuthActionsTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  MARKETING_PATHS = %w[/home /blog /about /terms /privacy].freeze

  # --- Navbar (all 5 pages) ---

  test "unauthenticated marketing pages show Login link and Get started button" do
    MARKETING_PATHS.each do |path|
      get path
      assert_response :success, "GET #{path}"
      assert_select "nav a[href=?]", login_path, text: "Login"
      assert_select "nav button[data-action*=signup-modal]", text: "Get started"
    end
  end

  test "authenticated marketing pages show New Episode link and Logout button" do
    sign_in_as(users(:one))

    MARKETING_PATHS.each do |path|
      get path
      assert_response :success, "GET #{path} while authenticated"
      assert_select "nav a[href=?]", new_episode_path, text: /New Episode/
      assert_select "nav form[action=?][method=post]", session_path do
        assert_select "button", text: "Logout"
      end
      assert_select "nav a[href=?]", login_path, count: 0
    end
  end

  # --- Mobile menu (actions must render, not just links) ---

  test "mobile menu dialog renders actions when authenticated" do
    sign_in_as(users(:one))
    get "/home"
    assert_response :success

    # Mobile dialog is inside <nav>, wraps links + actions in its own panel.
    assert_select "dialog#mobile-menu a[href=?]", new_episode_path, text: /New Episode/
    assert_select "dialog#mobile-menu form[action=?][method=post]", session_path do
      assert_select "button", text: "Logout"
    end
  end

  test "mobile menu dialog renders actions when logged out" do
    get "/home"
    assert_response :success
    assert_select "dialog#mobile-menu a[href=?]", login_path, text: "Login"
    assert_select "dialog#mobile-menu button[data-action*=signup-modal]", text: "Get started"
  end

  # --- Blog hero CTA ---

  test "blog hero CTA swaps to New Episode link when authenticated" do
    sign_in_as(users(:one))
    get "/blog"
    assert_response :success

    assert_select "a[href=?]", new_episode_path, text: /New Episode/
    assert_select "button[data-action*=signup-modal]", text: "Create your first episode", count: 0
  end

  test "blog hero CTA remains signup-modal button when logged out" do
    get "/blog"
    assert_response :success
    assert_select "button[data-action*=signup-modal]", text: "Create your first episode"
  end

  # --- Home body CTAs (hero + 6 pricing tiers + final) ---

  test "home body CTAs route directly when authenticated" do
    sign_in_as(users(:one))
    get "/home"
    assert_response :success

    # Hero CTA (plan=free) becomes a direct link to new_episode_path.
    assert_select "a[href=?]", new_episode_path, text: "Create my feed"

    # Each credit-pack tier's button becomes a checkout link with its own pack_size.
    AppConfig::Credits::PACKS.each do |pack|
      assert_select "a[href=?]", checkout_path(pack_size: pack[:size]), text: "Buy #{pack[:label]}"
    end

    # No credit-pack signup-modal buttons should remain for authenticated users.
    assert_select "button[data-action*=signup-modal][data-plan=credit_pack]", count: 0
  end

  test "home body CTAs remain signup-modal buttons when logged out" do
    get "/home"
    assert_response :success
    assert_select "button[data-action*=signup-modal][data-plan=free]", text: "Create my feed"
    AppConfig::Credits::PACKS.each do |pack|
      assert_select "button[data-action*=signup-modal][data-plan=credit_pack][data-pack-size=?]", pack[:size].to_s, text: "Buy #{pack[:label]}"
    end
  end

  # --- Final CTA block (home + about) — regression coverage for agent-team-x4e6 ---
  # The final CTA used to render an empty <div class="flex items-center gap-4"></div>
  # because a nested link_to-with-block inside safe_join inside tag.div-with-block
  # confused Rails' capture/output-buffer interaction. These tests lock in that
  # both the primary CTA and the secondary "see more" link render inside the
  # flex row.

  test "home final CTA renders primary button and secondary link when logged out" do
    get "/home"
    assert_response :success
    assert_select "div.flex.items-center.gap-4" do
      assert_select "button[data-action*=signup-modal][data-plan=free]", text: "Start listening free"
      assert_select "a[href='#features']", text: /See how it works/
    end
  end

  test "home final CTA renders primary link and secondary link when authenticated" do
    sign_in_as(users(:one))
    get "/home"
    assert_response :success
    assert_select "div.flex.items-center.gap-4" do
      assert_select "a[href=?]", new_episode_path, text: "Start listening free"
      assert_select "a[href='#features']", text: /See how it works/
    end
  end

  test "about final CTA renders primary button and secondary link when logged out" do
    get "/about"
    assert_response :success
    assert_select "div.flex.items-center.gap-4" do
      assert_select "button[data-action*=signup-modal][data-plan=free]", text: "Try PodRead free"
      assert_select "a[href='/#pricing']", text: /View pricing/
    end
  end

  test "about final CTA renders primary link and secondary link when authenticated" do
    sign_in_as(users(:one))
    get "/about"
    assert_response :success
    assert_select "div.flex.items-center.gap-4" do
      assert_select "a[href=?]", new_episode_path, text: "Try PodRead free"
      assert_select "a[href='/#pricing']", text: /View pricing/
    end
  end

  # --- Behavioral logout test (agent-team-rl97) ---
  # The other tests assert the Logout form RENDERS. This test exercises the
  # form: DELETE /session must actually terminate the session, so a subsequent
  # marketing page renders as logged-out.

  test "posting to the logout form ends the session" do
    sign_in_as(users(:one))
    get "/home"
    assert_select "nav a[href=?]", new_episode_path, text: /New Episode/

    delete session_path
    follow_redirect!

    get "/home"
    assert_select "nav a[href=?]", login_path, text: "Login"
    assert_select "nav a[href=?]", new_episode_path, count: 0
  end
end
