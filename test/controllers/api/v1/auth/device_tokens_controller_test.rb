require "test_helper"

module Api
  module V1
    module Auth
      class DeviceTokensControllerTest < ActionDispatch::IntegrationTest
        test "returns authorization_pending for unconfirmed code" do
          pending_code = device_codes(:pending)

          post api_v1_auth_device_tokens_path, params: { device_code: pending_code.user_code }

          assert_response :precondition_required
          json = response.parsed_body
          assert_equal "authorization_pending", json["error"]
        end

        test "returns expired_token for expired code" do
          expired_code = device_codes(:expired)

          post api_v1_auth_device_tokens_path, params: { device_code: expired_code.user_code }

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

          post api_v1_auth_device_tokens_path, params: { device_code: confirmed_code.user_code }

          assert_response :ok
          json = response.parsed_body
          assert json["access_token"].present?
          assert_equal users(:one).email_address, json["user_email"]
        end

        test "does not require authentication" do
          pending_code = device_codes(:pending)

          post api_v1_auth_device_tokens_path, params: { device_code: pending_code.user_code }

          # Should not be 401 - should be 428 (pending)
          assert_response :precondition_required
        end
      end
    end
  end
end
