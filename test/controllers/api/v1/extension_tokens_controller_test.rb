require "test_helper"

module Api
  module V1
    class ExtensionTokensControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
      end

      test "create returns 401 when not logged in" do
        post api_v1_extension_token_path

        assert_response :redirect
        # Redirects to login when not authenticated
      end

      test "create returns token when logged in" do
        sign_in_as(@user)

        post api_v1_extension_token_path

        assert_response :success
        json = response.parsed_body
        assert json["token"].present?
        assert json["token"].start_with?("pk_live_")
      end

      test "create generates a valid token that can be used for API auth" do
        sign_in_as(@user)

        post api_v1_extension_token_path

        assert_response :success
        token = response.parsed_body["token"]

        # Verify the token works for API authentication
        api_token = FindsApiToken.call(plain_token:token)
        assert_not_nil api_token
        assert_equal @user, api_token.user
        assert api_token.active?
      end

      test "create revokes previous tokens for user" do
        sign_in_as(@user)

        # Generate first token
        post api_v1_extension_token_path
        first_token = response.parsed_body["token"]
        first_api_token = FindsApiToken.call(plain_token:first_token)

        # Generate second token
        post api_v1_extension_token_path
        second_token = response.parsed_body["token"]

        # First token should now be revoked
        first_api_token.reload
        assert first_api_token.revoked?

        # Second token should be active
        second_api_token = FindsApiToken.call(plain_token:second_token)
        assert second_api_token.active?
      end

      test "create returns different token each time" do
        sign_in_as(@user)

        post api_v1_extension_token_path
        first_token = response.parsed_body["token"]

        post api_v1_extension_token_path
        second_token = response.parsed_body["token"]

        assert_not_equal first_token, second_token
      end
    end
  end
end
