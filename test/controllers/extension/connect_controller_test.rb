require "test_helper"

module Extension
  class ConnectControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
    end

    test "show requires authentication" do
      get extension_connect_path

      assert_response :redirect
      # Redirects to login when not authenticated
    end

    test "show renders connect page with token when logged in" do
      sign_in_as(@user)

      get extension_connect_path

      assert_response :success
      # Check that a token starting with prefix is present in the page (passed to extension via JS)
      assert_match(/sk_live_/, response.body)
    end

    test "show generates a valid API token" do
      sign_in_as(@user)

      assert_difference "ApiToken.count", 1 do
        get extension_connect_path
      end

      # Extract token from response body
      token_match = response.body.match(/sk_live_[A-Za-z0-9_-]+/)
      assert token_match, "Expected to find token in response"

      token = token_match[0]
      api_token = FindsApiToken.call(plain_token: token)
      assert_not_nil api_token
      assert_equal @user, api_token.user
      assert api_token.active?
    end

    test "show revokes previous extension tokens for user" do
      sign_in_as(@user)

      # First reconnect — generate extension token
      get extension_connect_path
      first_token_match = response.body.match(/sk_live_[A-Za-z0-9_-]+/)
      first_api_token = FindsApiToken.call(plain_token: first_token_match[0])
      assert first_api_token.active?
      assert_equal "extension", first_api_token.source

      # Second reconnect — should revoke the first and issue a new one
      get extension_connect_path
      second_token_match = response.body.match(/sk_live_[A-Za-z0-9_-]+/)

      first_api_token.reload
      assert first_api_token.revoked?

      second_api_token = FindsApiToken.call(plain_token: second_token_match[0])
      assert second_api_token.active?
      assert_equal "extension", second_api_token.source
    end

    test "show does not revoke user-created tokens when reconnecting" do
      sign_in_as(@user)

      user_created_token = api_tokens(:user_created_token)
      assert user_created_token.active?
      assert_equal "user", user_created_token.source

      get extension_connect_path

      user_created_token.reload
      assert user_created_token.active?,
        "user-created tokens must survive an extension reconnect"
    end

    test "show does not revoke OTHER users' extension tokens" do
      other_user = users(:two)
      other_user_extension_token = api_tokens(:recently_used_token)
      assert_equal other_user, other_user_extension_token.user
      assert other_user_extension_token.source_extension?
      assert other_user_extension_token.active?

      sign_in_as(@user)
      get extension_connect_path

      other_user_extension_token.reload
      assert other_user_extension_token.active?,
        "reconnecting user A must never touch user B's extension tokens"
    end

    test "show includes data attribute for extension to read" do
      sign_in_as(@user)

      get extension_connect_path

      assert_response :success
      assert_match(/data-tts-token/, response.body)
      assert_match(/data-tts-connect-status/, response.body)
    end
  end
end
