# frozen_string_literal: true

require "test_helper"

class MarketingAuthActionsTest < ActionDispatch::IntegrationTest
  AUTHENTICATED_PATHS = %w[/home /blog /about /terms /privacy].freeze

  test "unauthenticated marketing pages show Login link and Get started button" do
    AUTHENTICATED_PATHS.each do |path|
      get path
      assert_response :success, "GET #{path}"
      assert_select "nav a[href=?]", login_path, text: "Login"
      assert_select "nav button[data-action*=signup-modal]", text: "Get started"
    end
  end

  test "authenticated marketing pages show New Episode link and Logout button" do
    sign_in_as(users(:one))

    AUTHENTICATED_PATHS.each do |path|
      get path
      assert_response :success, "GET #{path} while authenticated"
      assert_select "nav a[href=?]", new_episode_path, text: /New Episode/
      assert_select "nav form[action=?][method=post]", session_path do
        assert_select "button", text: "Logout"
      end
      assert_select "nav a[href=?]", login_path, count: 0
    end
  end

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
end
