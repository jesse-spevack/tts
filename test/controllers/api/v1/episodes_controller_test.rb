require "test_helper"

module Api
  module V1
    class EpisodesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @api_token = GeneratesApiToken.call(user: @user)
        @plain_token = @api_token.plain_token
        @valid_params = {
          title: "Test Article",
          author: "Test Author",
          description: "A test article description",
          content: "This is the full content of the article. " * 50,
          url: "https://example.com/article"
        }
      end

      test "create returns 401 without token" do
        post api_v1_episodes_path, params: @valid_params, as: :json

        assert_response :unauthorized
      end

      test "create returns 401 with invalid token" do
        post api_v1_episodes_path,
          params: @valid_params,
          headers: auth_header("invalid_token"),
          as: :json

        assert_response :unauthorized
      end

      test "create creates episode with valid token and params" do
        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(@plain_token),
            as: :json
        end

        assert_response :created
        json = response.parsed_body
        assert json["id"].present?
        assert json["id"].start_with?("ep_")
      end

      test "create returns episode for correct user" do
        post api_v1_episodes_path,
          params: @valid_params,
          headers: auth_header(@plain_token),
          as: :json

        episode = Episode.last
        assert_equal @user, episode.user
      end

      test "create sets extension source_type and stores source_url" do
        post api_v1_episodes_path,
          params: @valid_params,
          headers: auth_header(@plain_token),
          as: :json

        episode = Episode.last
        assert episode.extension?
        assert_equal "https://example.com/article", episode.source_url
      end

      test "create uses user's primary podcast" do
        podcast = @user.podcasts.first || CreatesDefaultPodcast.call(user: @user)

        post api_v1_episodes_path,
          params: @valid_params,
          headers: auth_header(@plain_token),
          as: :json

        episode = Episode.last
        assert_equal podcast, episode.podcast
      end

      test "create returns 422 with missing title" do
        post api_v1_episodes_path,
          params: @valid_params.except(:title),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
        assert response.parsed_body["error"].present?
      end

      test "create returns 422 with missing content" do
        post api_v1_episodes_path,
          params: @valid_params.except(:content),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
      end

      test "create returns 422 with missing url" do
        post api_v1_episodes_path,
          params: @valid_params.except(:url),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
      end

      test "create returns 403 when user exceeds free tier limit" do
        # Use a free user and max out their episode count
        free_user = users(:free_user)
        token = GeneratesApiToken.call(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES
        )

        post api_v1_episodes_path,
          params: @valid_params,
          headers: auth_header(token.plain_token),
          as: :json

        assert_response :forbidden
        assert_equal "Episode limit reached. Please upgrade your plan.", response.parsed_body["error"]
      end

      test "create records episode usage for free user" do
        free_user = users(:free_user)
        token = GeneratesApiToken.call(user: free_user)

        assert_difference -> { EpisodeUsage.current_for(free_user).episode_count }, 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(token.plain_token),
            as: :json
        end
      end

      test "create enqueues processing job" do
        assert_enqueued_with(job: ProcessesFileEpisodeJob) do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(@plain_token),
            as: :json
        end
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
