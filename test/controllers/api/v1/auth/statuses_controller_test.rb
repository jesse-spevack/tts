require "test_helper"

module Api
  module V1
    module Auth
      class StatusesControllerTest < ActionDispatch::IntegrationTest
        test "show returns 401 without token" do
          get api_v1_auth_status_path, as: :json

          assert_response :unauthorized
        end

        test "show returns email and tier for free user" do
          user = users(:free_user)
          token = GeneratesApiToken.call(user: user)

          get api_v1_auth_status_path,
            headers: auth_header(token.plain_token),
            as: :json

          assert_response :success
          json = response.parsed_body
          assert_equal user.email_address, json["email"]
          assert_equal "free", json["tier"]
          assert_equal 0, json["credits_remaining"]
          assert_equal AppConfig::Tiers::FREE_CHARACTER_LIMIT, json["character_limit"]
        end

        test "show returns premium tier for subscriber" do
          user = users(:subscriber)
          token = GeneratesApiToken.call(user: user)

          get api_v1_auth_status_path,
            headers: auth_header(token.plain_token),
            as: :json

          assert_response :success
          json = response.parsed_body
          assert_equal "premium", json["tier"]
        end

        test "show returns unlimited tier for unlimited user" do
          user = users(:unlimited_user)
          token = GeneratesApiToken.call(user: user)

          get api_v1_auth_status_path,
            headers: auth_header(token.plain_token),
            as: :json

          assert_response :success
          json = response.parsed_body
          assert_equal "unlimited", json["tier"]
          assert_nil json["character_limit"]
        end

        test "show returns premium tier for complimentary user" do
          user = users(:complimentary_user)
          token = GeneratesApiToken.call(user: user)

          get api_v1_auth_status_path,
            headers: auth_header(token.plain_token),
            as: :json

          assert_response :success
          json = response.parsed_body
          assert_equal "premium", json["tier"]
        end

        test "show returns credits remaining for credit user" do
          user = users(:credit_user)
          token = GeneratesApiToken.call(user: user)

          get api_v1_auth_status_path,
            headers: auth_header(token.plain_token),
            as: :json

          assert_response :success
          json = response.parsed_body
          assert_equal 3, json["credits_remaining"]
        end

        private

        def auth_header(token)
          { "Authorization" => "Bearer #{token}" }
        end
      end
    end
  end
end
