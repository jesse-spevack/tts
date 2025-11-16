require "test_helper"

module Api
  module Internal
    class EpisodesControllerTest < ActionDispatch::IntegrationTest
      setup do
        result = CreateUser.call(email_address: "test@example.com")
        @user = result.user
        @podcast = result.podcast
        @episode = @podcast.episodes.create!(
          title: "Test Episode",
          author: "Test Author",
          description: "Test description",
          status: "processing"
        )
        @secret = "test-callback-secret"
        ENV["HUB_CALLBACK_SECRET"] = @secret
      end

      test "update marks episode complete with valid secret" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "episode_abc123",
            audio_size_bytes: 1_000_000
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        @episode.reload
        assert_equal "complete", @episode.status
        assert_equal "episode_abc123", @episode.gcs_episode_id
        assert_equal 1_000_000, @episode.audio_size_bytes
      end

      test "update marks episode failed with error message" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "TTS service unavailable"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        @episode.reload
        assert_equal "failed", @episode.status
        assert_equal "TTS service unavailable", @episode.error_message
      end

      test "update rejects invalid secret" do
        patch api_internal_episode_url(@episode),
          params: { status: "complete" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => "wrong-secret"
          }

        assert_response :unauthorized
        @episode.reload
        assert_equal "processing", @episode.status
      end

      test "update rejects missing secret" do
        patch api_internal_episode_url(@episode),
          params: { status: "complete" }.to_json,
          headers: { "Content-Type" => "application/json" }

        assert_response :unauthorized
      end

      test "update returns 404 for non-existent episode" do
        patch api_internal_episode_url(id: 99999),
          params: { status: "complete" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :not_found
      end

      test "update rejects invalid status" do
        patch api_internal_episode_url(@episode),
          params: { status: "invalid_status" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :unprocessable_entity
        @episode.reload
        assert_equal "processing", @episode.status
      end

      test "update is idempotent for duplicate completions" do
        @episode.update!(status: "complete", gcs_episode_id: "episode_abc123")

        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "episode_abc123",
            audio_size_bytes: 1_000_000
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
      end
    end
  end
end
