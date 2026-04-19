require "test_helper"

module Api
  module V1
    class EpisodesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @api_token = GeneratesApiToken.call(user: @user)
        @plain_token = @api_token.plain_token
        @valid_params = {
          source_type: "extension",
          title: "Test Article",
          author: "Test Author",
          description: "A test article description",
          content: "This is the full content of the article. " * 50,
          url: "https://example.com/article"
        }
      end

      # === INDEX ===

      test "index returns 401 without token" do
        get api_v1_episodes_path, as: :json

        assert_response :unauthorized
      end

      test "index returns user's episodes" do
        get api_v1_episodes_path,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body
        assert json["episodes"].is_a?(Array)
        assert json["meta"].present?
        assert json["meta"]["total"].present?

        # Should only include current user's episodes
        json["episodes"].each do |ep|
          episode = Episode.find_by_prefix_id(ep["id"])
          assert_equal @user.id, episode.user_id
        end
      end

      test "index returns episodes newest first" do
        get api_v1_episodes_path,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        episodes = response.parsed_body["episodes"]
        next if episodes.length < 2

        dates = episodes.map { |ep| Time.parse(ep["created_at"]) }
        assert_equal dates.sort.reverse, dates
      end

      test "index paginates results" do
        get api_v1_episodes_path,
          params: { page: 1, limit: 2 },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body
        assert json["episodes"].length <= 2
        assert_equal 1, json["meta"]["page"]
        assert_equal 2, json["meta"]["limit"]
      end

      test "index caps limit at 100" do
        get api_v1_episodes_path,
          params: { limit: 500 },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        assert_equal 100, response.parsed_body["meta"]["limit"]
      end

      test "index clamps page below 1 to 1" do
        get api_v1_episodes_path,
          params: { page: 0 },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        assert_equal 1, response.parsed_body["meta"]["page"]
      end

      test "index clamps negative page to 1" do
        get api_v1_episodes_path,
          params: { page: -5 },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        assert_equal 1, response.parsed_body["meta"]["page"]
      end

      test "index clamps limit below 1 to 1" do
        get api_v1_episodes_path,
          params: { limit: 0 },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        assert_equal 1, response.parsed_body["meta"]["limit"]
      end

      test "index clamps negative limit to 1" do
        get api_v1_episodes_path,
          params: { limit: -10 },
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        assert_equal 1, response.parsed_body["meta"]["limit"]
      end

      test "index does not return other users episodes" do
        other_user = users(:two)
        other_token = GeneratesApiToken.call(user: other_user)

        get api_v1_episodes_path,
          headers: auth_header(other_token.plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body
        json["episodes"].each do |ep|
          episode = Episode.find_by_prefix_id(ep["id"])
          assert_equal other_user.id, episode.user_id
        end
      end

      test "index does not return soft-deleted episodes" do
        # Soft-delete an episode owned by user one
        episode = episodes(:one)
        episode.soft_delete!

        get api_v1_episodes_path,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        ids = response.parsed_body["episodes"].map { |ep| ep["id"] }
        assert_not_includes ids, episode.prefix_id
      end

      # === SHOW ===

      test "show returns 401 without token" do
        episode = episodes(:one)
        get api_v1_episode_path(episode.prefix_id), as: :json

        assert_response :unauthorized
      end

      test "show returns episode details" do
        episode = episodes(:one)
        get api_v1_episode_path(episode.prefix_id),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :success
        json = response.parsed_body["episode"]
        assert_equal episode.prefix_id, json["id"]
        assert_equal episode.title, json["title"]
        assert_equal episode.status, json["status"]
        assert_equal episode.source_type, json["source_type"]
        assert json["created_at"].present?
      end

      test "show returns 404 for other users episode" do
        other_episode = episodes(:two)
        get api_v1_episode_path(other_episode.prefix_id),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :not_found
      end

      test "show returns 404 for nonexistent episode" do
        get api_v1_episode_path("ep_nonexistent"),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :not_found
      end

      # === CREATE (existing extension flow) ===

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

      # === CREATE — 402 "upgrade" shape (agent-team-909) ===
      #
      # /api/v1/episodes is Path 1: authenticated + credits only. When a user
      # is out of credits we return a 402 that points them at the billing
      # upgrade URL — NOT an MPP challenge. MPP creation lives on /mpp/*.

      test "create returns 402 upgrade shape when authenticated user is out of credits" do
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

        assert_response :payment_required
        json = response.parsed_body
        assert_equal "Payment required", json["error"]
        assert_equal 0, json["credits_remaining"]
        assert_equal false, json["subscription_active"]
        assert_equal "#{AppConfig::Domain::BASE_URL}/billing", json["upgrade_url"]
      end

      test "create 402 upgrade response does not include WWW-Authenticate header" do
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

        assert_response :payment_required
        assert_nil response.headers["WWW-Authenticate"],
          "Path 1 upgrade 402 must not include WWW-Authenticate — MPP lives on /mpp/*"
      end

      test "create 402 upgrade response does not include MPP challenge key" do
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

        assert_response :payment_required
        json = response.parsed_body
        assert_nil json["challenge"],
          "Path 1 upgrade 402 must not include an MPP challenge — redirect clients to /mpp/* for that"
      end

      test "create returns 402 upgrade even when a Payment header is attached (MPP not accepted on /episodes)" do
        free_user = users(:free_user)
        token = GeneratesApiToken.call(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES
        )

        headers = {
          "Authorization" => "Bearer #{token.plain_token}, Payment anything_goes_here"
        }

        post api_v1_episodes_path, params: @valid_params, headers: headers, as: :json

        assert_response :payment_required
        json = response.parsed_body
        assert_equal "Payment required", json["error"]
        assert_equal "#{AppConfig::Domain::BASE_URL}/billing", json["upgrade_url"]
        assert_nil json["challenge"]
      end

      test "create returns 402 upgrade when Payment header is malformed (header is ignored)" do
        free_user = users(:free_user)
        token = GeneratesApiToken.call(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES
        )

        headers = {
          "Authorization" => "Bearer #{token.plain_token}, Payment !!not-base64!!"
        }

        post api_v1_episodes_path, params: @valid_params, headers: headers, as: :json

        assert_response :payment_required
        json = response.parsed_body
        assert_equal "#{AppConfig::Domain::BASE_URL}/billing", json["upgrade_url"]
      end

      test "create returns 201 for subscriber with bearer token (no credit check needed)" do
        subscriber = users(:subscriber)
        token = GeneratesApiToken.call(user: subscriber)

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(token.plain_token),
            as: :json
        end

        assert_response :created
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

      test "create deducts credit for credit user" do
        credit_user = users(:credit_user)
        token = GeneratesApiToken.call(user: credit_user)

        assert_difference "CreditTransaction.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(token.plain_token),
            as: :json
        end

        assert_response :created
      end

      test "create enqueues processing job" do
        assert_enqueued_with(job: ProcessesFileEpisodeJob) do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(@plain_token),
            as: :json
        end
      end

      test "create returns 429 when user exceeds hourly rate limit" do
        # Clear any existing episodes so we have a clean slate for rate limit test
        @user.episodes.unscoped.delete_all
        create_recent_episodes(20)

        post api_v1_episodes_path,
          params: @valid_params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :too_many_requests
        assert_equal "You've reached your hourly episode limit", response.parsed_body["error"]
      end

      test "create succeeds when user is under hourly rate limit" do
        # Clear any existing episodes so we have a clean slate for rate limit test
        @user.episodes.unscoped.delete_all
        create_recent_episodes(19)

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: auth_header(@plain_token),
            as: :json
        end

        assert_response :created
      end

      # === CREATE with source_type=url ===

      test "create with source_type url creates url episode" do
        params = { source_type: "url", url: "https://example.com/article" }

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: params,
            headers: auth_header(@plain_token),
            as: :json
        end

        assert_response :created
        episode = Episode.last
        assert episode.url?
      end

      test "create with source_type url returns 422 for invalid url" do
        params = { source_type: "url", url: "not-a-url" }

        post api_v1_episodes_path,
          params: params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
      end

      # === CREATE with source_type=text ===

      test "create with source_type text creates paste episode" do
        text = "A" * 200
        params = { source_type: "text", text: text, title: "My Text", author: "Me" }

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: params,
            headers: auth_header(@plain_token),
            as: :json
        end

        assert_response :created
        episode = Episode.last
        assert episode.paste?
        assert_equal "My Text", episode.title
      end

      test "create with source_type text returns 422 for short text" do
        params = { source_type: "text", text: "too short" }

        post api_v1_episodes_path,
          params: params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
      end

      # === CREATE with missing/invalid source_type ===

      test "create without source_type returns 422" do
        params = { title: "Test", content: "content " * 50 }

        post api_v1_episodes_path,
          params: params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["error"], "source_type is required"
      end

      test "create with invalid source_type returns 422" do
        params = { source_type: "garbage", title: "Test", content: "content " * 50 }

        post api_v1_episodes_path,
          params: params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["error"], "source_type must be"
      end

      test "create with source_type file returns 422 read-only error" do
        params = { source_type: "file", title: "Test" }

        post api_v1_episodes_path,
          params: params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["error"], "'file' is read-only"
      end

      test "create with source_type email returns 422 read-only error" do
        params = { source_type: "email", title: "Test" }

        post api_v1_episodes_path,
          params: params,
          headers: auth_header(@plain_token),
          as: :json

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["error"], "'email' is read-only"
      end

      # === DESTROY ===

      test "destroy returns 401 without token" do
        episode = episodes(:one)
        delete api_v1_episode_path(episode.prefix_id), as: :json

        assert_response :unauthorized
      end

      test "destroy enqueues DeleteEpisodeJob" do
        episode = episodes(:one)

        assert_enqueued_with(job: DeleteEpisodeJob) do
          delete api_v1_episode_path(episode.prefix_id),
            headers: auth_header(@plain_token),
            as: :json
        end

        assert_response :success
        assert response.parsed_body["deleted"]
      end

      test "destroy returns 404 for other users episode" do
        other_episode = episodes(:two)
        delete api_v1_episode_path(other_episode.prefix_id),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :not_found
      end

      test "destroy returns 404 for nonexistent episode" do
        delete api_v1_episode_path("ep_nonexistent"),
          headers: auth_header(@plain_token),
          as: :json

        assert_response :not_found
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end

      def create_recent_episodes(count)
        podcast = @user.podcasts.first || CreatesDefaultPodcast.call(user: @user)

        count.times do |i|
          Episode.create!(
            user: @user,
            podcast: podcast,
            title: "Rate limit test episode #{i}",
            author: "Test Author",
            description: "Test description",
            source_type: :url,
            source_url: "https://example.com/article-#{i}",
            status: :pending
          )
        end
      end
    end
  end
end
