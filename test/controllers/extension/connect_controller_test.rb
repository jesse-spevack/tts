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
      assert_match(/pk_live_/, response.body)
    end

    test "show generates a valid API token" do
      sign_in_as(@user)

      assert_difference "ApiToken.count", 1 do
        get extension_connect_path
      end

      # Extract token from response body
      token_match = response.body.match(/pk_live_[A-Za-z0-9_-]+/)
      assert token_match, "Expected to find token in response"

      token = token_match[0]
      api_token = FindsApiToken.call(plain_token:token)
      assert_not_nil api_token
      assert_equal @user, api_token.user
      assert api_token.active?
    end

    test "show revokes previous tokens for user" do
      sign_in_as(@user)

      # Generate first token
      get extension_connect_path
      first_token_match = response.body.match(/pk_live_[A-Za-z0-9_-]+/)
      first_api_token = FindsApiToken.call(plain_token:first_token_match[0])
      assert first_api_token.active?

      # Generate second token
      get extension_connect_path
      second_token_match = response.body.match(/pk_live_[A-Za-z0-9_-]+/)

      # First token should now be revoked
      first_api_token.reload
      assert first_api_token.revoked?

      # Second token should be active
      second_api_token = FindsApiToken.call(plain_token:second_token_match[0])
      assert second_api_token.active?
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
