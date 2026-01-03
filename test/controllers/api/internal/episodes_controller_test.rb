require "test_helper"

module Api
  module Internal
    class EpisodesControllerTest < ActionDispatch::IntegrationTest
      setup do
        result = CreateUser.call(email_address: "test@example.com")
        @user = result.data[:user]
        @podcast = result.data[:podcast]
        @episode = @podcast.episodes.create!(
          title: "Test Episode",
          author: "Test Author",
          description: "Test description",
          user: @user,
          source_type: :url,
          source_url: "https://example.com/test-article",
          status: :processing
        )
        @secret = "test-callback-secret"
        ENV["GENERATOR_CALLBACK_SECRET"] = @secret
      end

      test "update marks episode complete with valid secret" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "episode_abc123",
            audio_size_bytes: 1_000_000,
            duration_seconds: 754
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
        assert_equal 754, @episode.duration_seconds
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
        @episode.update!(status: :complete, gcs_episode_id: "episode_abc123")

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

      test "refunds episode usage when status is failed for free user" do
        free_user = users(:free_user)
        @episode.update!(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: 1
        )

        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "Processing failed"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        usage = EpisodeUsage.current_for(free_user)
        assert_equal 0, usage.episode_count
      end

      test "does not refund usage when status is complete" do
        free_user = users(:free_user)
        @episode.update!(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: 1
        )

        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "abc123"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        usage = EpisodeUsage.current_for(free_user)
        assert_equal 1, usage.episode_count
      end

      test "handles failure update when no usage record exists" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "Processing failed"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        @episode.reload
        assert_equal "failed", @episode.status
      end

      test "calls NotifiesEpisodeCompletion when episode completes" do
        @episode.update!(status: :pending)

        assert_emails 1 do
          patch api_internal_episode_url(@episode),
            params: { status: "complete", gcs_episode_id: "episode_abc123" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end
      end

      test "does not send email when episode fails" do
        @episode.update!(status: :pending)

        assert_no_emails do
          patch api_internal_episode_url(@episode),
            params: { status: "failed", error_message: "Processing error" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end
      end

      test "does not send duplicate emails on repeated completion updates" do
        @episode.update!(status: :pending)

        # First completion - should send email
        assert_emails 1 do
          patch api_internal_episode_url(@episode),
            params: { status: "complete", gcs_episode_id: "episode_abc123" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end

        # Second completion - should not send email
        assert_no_emails do
          patch api_internal_episode_url(@episode),
            params: { status: "complete", gcs_episode_id: "episode_abc123" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end
      end
    end
  end
end
