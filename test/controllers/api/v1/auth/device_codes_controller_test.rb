require "test_helper"

module Api
  module V1
    module Auth
      class DeviceCodesControllerTest < ActionDispatch::IntegrationTest
        test "create returns device code without authentication" do
          post api_v1_auth_device_codes_path

          assert_response :ok
          json = response.parsed_body
          assert json["device_code"].present?
          assert json["user_code"].present?
          assert json["verification_url"].present?
          assert_equal 900, json["expires_in"]
          assert_equal 5, json["interval"]
        end

        test "create returns user_code in XXXX-XXXX format" do
          post api_v1_auth_device_codes_path

          json = response.parsed_body
          assert_match(/\A[A-Z]{4}-[A-Z]{4}\z/, json["user_code"])
        end

        test "create returns a verification_url with code param" do
          post api_v1_auth_device_codes_path

          json = response.parsed_body
          assert json["verification_url"].include?("/auth/device?code=")
          assert_match(/code=[A-Z]{4}-[A-Z]{4}\z/, json["verification_url"])
        end

        test "create generates unique codes each time" do
          post api_v1_auth_device_codes_path
          first = response.parsed_body

          post api_v1_auth_device_codes_path
          second = response.parsed_body

          assert_not_equal first["device_code"], second["device_code"]
          assert_not_equal first["user_code"], second["user_code"]
        end

        test "create persists the device code" do
          assert_difference "DeviceCode.count", 1 do
            post api_v1_auth_device_codes_path
          end
        end
      end
    end
  end
end
