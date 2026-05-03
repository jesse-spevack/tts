require "test_helper"

module Api
  module V1
    module Auth
      class SessionsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @user = users(:one)
        end

        test "exchanges valid magic-link token for an API token" do
          token = GeneratesAuthToken.call(user: @user)

          assert_difference -> { ApiToken.where(source: "android").count }, 1 do
            post api_v1_auth_sessions_path, params: { token: token }
          end

          assert_response :ok
          json = response.parsed_body
          assert json["access_token"].present?
          assert json["access_token"].start_with?("sk_live_")
          assert_equal @user.email_address, json["user_email"]
        end

        test "returns 401 for invalid token" do
          post api_v1_auth_sessions_path, params: { token: "not-a-real-token" }

          assert_response :unauthorized
          assert_equal "invalid_or_expired", response.parsed_body["error"]
        end

        test "returns 401 when token is replayed after first success" do
          token = GeneratesAuthToken.call(user: @user)

          post api_v1_auth_sessions_path, params: { token: token }
          assert_response :ok

          post api_v1_auth_sessions_path, params: { token: token }
          assert_response :unauthorized
          assert_equal "invalid_or_expired", response.parsed_body["error"]
        end
      end
    end
  end
end
