require "test_helper"

module Settings
  class ApiTokenRevealsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
    end

    test "show redirects to login when not authenticated" do
      get settings_api_token_reveal_path

      assert_response :redirect
    end

    test "show renders the plain token passed through flash from create" do
      sign_in_as(@user)

      post settings_api_tokens_path
      follow_redirect!

      assert_response :success
      new_token = @user.api_tokens.source_user.order(created_at: :desc).first

      # Plain token is never persisted — assert the rendered body contains a
      # string that hashes to the DB digest (proves the reveal genuinely
      # exposed the freshly-minted plain token).
      rendered = response.body.match(/sk_live_[A-Za-z0-9_-]+/)&.to_s
      assert rendered, "reveal page must contain an sk_live_ token in the response body"
      assert_equal new_token.token_digest, HashesToken.call(plain_token: rendered)
      assert_includes response.body, new_token.token_prefix
    end

    test "show redirects to index when visited directly without a token in flash" do
      sign_in_as(@user)

      get settings_api_token_reveal_path

      assert_redirected_to settings_api_tokens_path
    end

    test "show does not re-reveal the token after the flash has been consumed" do
      sign_in_as(@user)

      # Create → reveal → follow to index (which clears the flash) → revisit reveal
      post settings_api_tokens_path
      follow_redirect! # reveal
      get settings_api_tokens_path # consumes flash
      get settings_api_token_reveal_path

      assert_redirected_to settings_api_tokens_path
    end
  end
end
