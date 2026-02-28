require "test_helper"

module Api
  module V1
    class FeedsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @api_token = GeneratesApiToken.call(user: @user)
        @plain_token = @api_token.plain_token
      end

      test "show returns 401 without token" do
        get api_v1_feed_path, as: :json

        assert_response :unauthorized
      end

      test "show returns the user's feed url" do
        get api_v1_feed_path,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body
        assert json["feed_url"].present?
        assert json["feed_url"].include?("podcast_")
      end

      test "show creates default podcast if user has none" do
        # Create a user with no podcast
        new_user = User.create!(email_address: "newuser-feed@example.com")
        token = GeneratesApiToken.call(user: new_user)

        get api_v1_feed_path,
          headers: auth_header(token.plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body
        assert json["feed_url"].present?
      end

      test "show returns 404 when primary_podcast is nil" do
        new_user = User.create!(email_address: "nopodcast-feed@example.com")
        token = GeneratesApiToken.call(user: new_user)

        Mocktail.replace(CreatesDefaultPodcast)
        stubs { |m| CreatesDefaultPodcast.call(user: m.any) }.with { nil }

        get api_v1_feed_path,
          headers: auth_header(token.plain_token),
          as: :json

        assert_response :not_found
        assert_equal "No podcast found", response.parsed_body["error"]
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
