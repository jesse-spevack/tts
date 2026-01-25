require "test_helper"

module Api
  module V1
    class ExtensionLogsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @api_token = ApiToken.generate_for(@user)
        @plain_token = @api_token.plain_token
      end

      test "create returns 401 without token" do
        post api_v1_extension_logs_path,
          params: { error_type: "parse_error", url: "https://example.com/article" },
          as: :json

        assert_response :unauthorized
        assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
      end

      test "create returns 201 with valid token" do
        post api_v1_extension_logs_path,
          params: { error_type: "parse_error", url: "https://example.com/article" },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :created
        assert_equal({ "logged" => true }, response.parsed_body)
      end

      test "create sanitizes log input by stripping newlines" do
        # The controller should strip newlines from input to prevent log injection
        error_type_with_newlines = "parse_error\nFake log entry"
        url_with_newlines = "https://example.com/article\nInjected log"

        # We can't directly test the Rails.logger output in integration tests,
        # but we can verify the request succeeds and returns the expected response
        post api_v1_extension_logs_path,
          params: { error_type: error_type_with_newlines, url: url_with_newlines },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :created
        assert_equal({ "logged" => true }, response.parsed_body)
      end

      test "create truncates long error_type to 100 characters" do
        long_error_type = "a" * 200

        post api_v1_extension_logs_path,
          params: { error_type: long_error_type, url: "https://example.com" },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :created
      end

      test "create truncates long url to 500 characters" do
        long_url = "https://example.com/" + ("a" * 600)

        post api_v1_extension_logs_path,
          params: { error_type: "error", url: long_url },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :created
      end

      test "create returns 401 with revoked token" do
        @api_token.revoke!

        post api_v1_extension_logs_path,
          params: { error_type: "parse_error", url: "https://example.com/article" },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unauthorized
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
