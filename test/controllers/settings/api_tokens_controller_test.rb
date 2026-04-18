require "test_helper"

module Settings
  class ApiTokensControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
    end

    # Authentication
    test "index redirects to login when not authenticated" do
      get settings_api_tokens_path

      assert_response :redirect
    end

    test "create redirects to login when not authenticated" do
      post settings_api_tokens_path

      assert_response :redirect
    end

    test "destroy redirects to login when not authenticated" do
      token = api_tokens(:user_created_token)

      delete settings_api_token_path(token)

      assert_response :redirect
    end

    # Index
    test "index lists only user-created active tokens for the current user" do
      sign_in_as(@user)

      get settings_api_tokens_path

      assert_response :success
      assert_select "td", text: api_tokens(:user_created_token).token_prefix
      # Extension-sourced tokens must not appear — they're managed elsewhere
      assert_select "td", text: api_tokens(:active_token).token_prefix.to_s, count: 0
    end

    test "index does not show other users' tokens" do
      other_users_token = api_tokens(:recently_used_token)
      assert_equal users(:two), other_users_token.user

      sign_in_as(@user)

      get settings_api_tokens_path

      assert_select "td", text: other_users_token.token_prefix.to_s, count: 0
    end

    test "index does not show revoked tokens" do
      sign_in_as(@user)

      # Revoke the user_created_token
      RevokesApiToken.call(token: api_tokens(:user_created_token))

      get settings_api_tokens_path

      assert_response :success
      assert_select "td", text: api_tokens(:user_created_token).token_prefix.to_s, count: 0
    end

    # Create + Reveal (PRG)
    test "create generates a new user-sourced token and redirects to reveal" do
      sign_in_as(@user)

      assert_difference "ApiToken.count", 1 do
        post settings_api_tokens_path
      end

      assert_redirected_to reveal_settings_api_tokens_path
      new_token = @user.api_tokens.source_user.order(created_at: :desc).first
      assert_equal "user", new_token.source
      assert_equal new_token.token_prefix, flash[:reveal_token_prefix]
      # The plain token ridden in flash must hash to the persisted digest
      assert_equal new_token.token_digest,
        HashesToken.call(plain_token: flash[:reveal_plain_token])
    end

    test "reveal renders the plain token passed through flash" do
      sign_in_as(@user)

      post settings_api_tokens_path
      follow_redirect!

      assert_response :success
      new_token = @user.api_tokens.source_user.order(created_at: :desc).first

      # Plain token is never stored — assert the rendered body contains a
      # string that hashes to the DB digest (proves the reveal action
      # genuinely exposed the freshly-minted plain token).
      rendered = response.body.match(/sk_live_[A-Za-z0-9_-]+/)&.to_s
      assert rendered, "reveal page must contain an sk_live_ token in the response body"
      assert_equal new_token.token_digest, HashesToken.call(plain_token: rendered)
      assert_includes response.body, new_token.token_prefix
    end

    test "reveal redirects to index when visited directly without a token in flash" do
      sign_in_as(@user)

      get reveal_settings_api_tokens_path

      assert_redirected_to settings_api_tokens_path
    end

    test "reveal does not re-show the token after the flash has been consumed" do
      sign_in_as(@user)

      # Create → reveal → follow to index (which clears the flash) → revisit reveal
      post settings_api_tokens_path
      follow_redirect! # reveal
      get settings_api_tokens_path # consumes flash
      get reveal_settings_api_tokens_path

      assert_redirected_to settings_api_tokens_path
    end

    test "create does not revoke user's other active tokens" do
      sign_in_as(@user)

      existing = api_tokens(:user_created_token)
      extension = api_tokens(:active_token)

      post settings_api_tokens_path

      existing.reload
      extension.reload
      assert existing.active?, "other user-created tokens must not be revoked"
      assert extension.active?, "extension tokens must not be revoked"
    end

    # Destroy
    test "destroy revokes a user's user-created token" do
      sign_in_as(@user)
      token = api_tokens(:user_created_token)

      delete settings_api_token_path(token)

      assert_redirected_to settings_api_tokens_path
      token.reload
      assert token.revoked?
    end

    test "destroy 404s for another user's token" do
      sign_in_as(@user)
      other_users_token = api_tokens(:recently_used_token)

      delete settings_api_token_path(other_users_token)

      assert_response :not_found
      other_users_token.reload
      assert other_users_token.active?
    end

    test "destroy 404s for an extension-sourced token" do
      sign_in_as(@user)
      extension_token = api_tokens(:active_token)
      assert_equal @user, extension_token.user

      delete settings_api_token_path(extension_token)

      assert_response :not_found
      extension_token.reload
      assert extension_token.active?
    end
  end
end
