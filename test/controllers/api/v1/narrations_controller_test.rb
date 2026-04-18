require "test_helper"

module Api
  module V1
    class NarrationsControllerTest < ActionDispatch::IntegrationTest
      # === SHOW — valid prefix_id, pending narration ===

      test "show returns 200 with status and metadata for pending narration" do
        narration = narrations(:one)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :ok
        json = response.parsed_body
        assert_equal narration.prefix_id, json["id"]
        assert_equal "pending", json["status"]
        assert_equal narration.title, json["title"]
        assert_equal narration.author, json["author"]
      end

      test "show does not include audio_url for pending narration" do
        narration = narrations(:one)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :ok
        json = response.parsed_body
        assert_nil json["audio_url"]
      end

      test "show does not include audio_url for processing narration" do
        narration = narrations(:processing)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :ok
        json = response.parsed_body
        assert_equal "processing", json["status"]
        assert_nil json["audio_url"]
      end

      # === SHOW — complete narration with audio ===

      test "show includes audio_url when narration is complete" do
        narration = narrations(:completed)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :ok
        json = response.parsed_body
        assert_equal "complete", json["status"]
        assert json["audio_url"].present?
        assert_includes json["audio_url"], narration.gcs_episode_id
      end

      test "show includes duration_seconds when narration is complete" do
        narration = narrations(:completed)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :ok
        json = response.parsed_body
        assert_equal narration.duration_seconds, json["duration_seconds"]
      end

      # === SHOW — expired narration ===

      test "show returns 404 for expired narration" do
        narration = narrations(:expired)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :not_found
      end

      # === SHOW — invalid prefix_id ===

      test "show returns 404 for nonexistent prefix_id" do
        get api_v1_narration_path("nar_does_not_exist_at_all"), as: :json

        assert_response :not_found
      end

      # === No authentication required ===

      test "show does not require bearer token" do
        narration = narrations(:one)

        get api_v1_narration_path(narration.prefix_id), as: :json

        assert_response :ok
      end

      # === Rate limiting ===

      test "rate limits narration show requests per IP" do
        narration = narrations(:one)

        # Use a fresh memory store for rate limiting
        memory_store = ActiveSupport::Cache::MemoryStore.new
        original_cache = Rack::Attack.cache.store
        Rack::Attack.cache.store = memory_store
        Rack::Attack.reset!

        freeze_time do
          # Make 60 requests (the limit)
          60.times do
            get api_v1_narration_path(narration.prefix_id), as: :json
            assert_response :ok
          end

          # The 61st request should be rate limited
          get api_v1_narration_path(narration.prefix_id), as: :json
          assert_response :too_many_requests
        end
      ensure
        unfreeze_time
        Rack::Attack.reset!
        Rack::Attack.cache.store = original_cache
      end
    end
  end
end
