require "test_helper"

module Api
  module V1
    module Auth
      class DeviceTokensControllerTest < ActionDispatch::IntegrationTest
        test "returns authorization_pending for unconfirmed code" do
          pending_code = device_codes(:pending)

          post api_v1_auth_device_tokens_path, params: { device_code: pending_code.device_code }

          assert_response :bad_request
          json = response.parsed_body
          assert_equal "authorization_pending", json["error"]
        end

        test "returns expired_token for expired code" do
          expired_code = device_codes(:expired)

          post api_v1_auth_device_tokens_path, params: { device_code: expired_code.device_code }

          assert_response :bad_request
          json = response.parsed_body
          assert_equal "expired_token", json["error"]
        end

        test "returns expired_token for unknown code" do
          post api_v1_auth_device_tokens_path, params: { device_code: "nonexistent" }

          assert_response :bad_request
          json = response.parsed_body
          assert_equal "expired_token", json["error"]
        end

        test "returns access_token for confirmed code" do
          confirmed_code = device_codes(:confirmed)

          post api_v1_auth_device_tokens_path, params: { device_code: confirmed_code.device_code }

          assert_response :ok
          json = response.parsed_body
          assert json["access_token"].present?
          assert json["access_token"].start_with?("sk_live_")
          assert_equal users(:one).email_address, json["user_email"]
        end

        test "stores token_digest after exchange" do
          confirmed_code = device_codes(:confirmed)

          post api_v1_auth_device_tokens_path, params: { device_code: confirmed_code.device_code }

          assert_response :ok
          confirmed_code.reload
          assert confirmed_code.token_digest.present?
        end

        test "returns expired_token for already exchanged code" do
          exchanged_code = device_codes(:exchanged)

          post api_v1_auth_device_tokens_path, params: { device_code: exchanged_code.device_code }

          assert_response :bad_request
          json = response.parsed_body
          assert_equal "expired_token", json["error"]
        end

        test "returned token is a valid API token" do
          confirmed_code = device_codes(:confirmed)

          post api_v1_auth_device_tokens_path, params: { device_code: confirmed_code.device_code }

          json = response.parsed_body
          api_token = FindsApiToken.call(plain_token: json["access_token"])
          assert_not_nil api_token
          assert_equal users(:one), api_token.user
          assert api_token.active?
        end

        test "does not require authentication" do
          pending_code = device_codes(:pending)

          post api_v1_auth_device_tokens_path, params: { device_code: pending_code.device_code }

          # Should not be 401 - should be 400 (pending per RFC 8628 section 3.5)
          assert_response :bad_request
        end
      end
    end
  end
end
