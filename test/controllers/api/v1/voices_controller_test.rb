require "test_helper"

module Api
  module V1
    class VoicesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @api_token = GeneratesApiToken.call(user: @user)
        @plain_token = @api_token.plain_token
      end

      test "index returns 401 without token" do
        get api_v1_voices_path, as: :json

        assert_response :unauthorized
      end

      test "index returns voices for free user" do
        get api_v1_voices_path,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body
        voices = json["voices"]
        assert voices.is_a?(Array)
        assert_equal AppConfig::Tiers::FREE_VOICES.length, voices.length

        voice_ids = voices.map { |v| v["id"] }
        AppConfig::Tiers::FREE_VOICES.each do |key|
          assert_includes voice_ids, key
        end
      end

      test "index returns all voices for unlimited user" do
        unlimited_user = users(:unlimited_user)
        token = GeneratesApiToken.call(user: unlimited_user)

        get api_v1_voices_path,
          headers: auth_header(token.plain_token),
          as: :json

        assert_response :success
        voices = response.parsed_body["voices"]
        assert_equal AppConfig::Tiers::PREMIUM_VOICES.length, voices.length

        voice_ids = voices.map { |v| v["id"] }
        AppConfig::Tiers::PREMIUM_VOICES.each do |key|
          assert_includes voice_ids, key
        end
      end

      test "index returns voice details" do
        get api_v1_voices_path,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        voice = response.parsed_body["voices"].first
        assert voice["id"].present?
        assert voice["name"].present?
        assert voice["accent"].present?
        assert voice["gender"].present?
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
