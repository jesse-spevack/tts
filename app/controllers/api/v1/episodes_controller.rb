module Api
  module V1
    class EpisodesController < BaseController
      before_action :check_episode_creation_permission, only: [ :create ]
      before_action :check_episode_rate_limit, only: [ :create ]

      def index
        episodes = current_user.episodes.newest_first
        page = [ (params[:page] || 1).to_i, 1 ].max
        limit = [ [ (params[:limit] || AppConfig::Api::DEFAULT_PER_PAGE).to_i, 1 ].max, AppConfig::Api::MAX_PER_PAGE ].min

        total = episodes.count
        episodes = episodes.offset((page - 1) * limit).limit(limit)

        render json: {
          episodes: episodes.map { |ep| serialize_episode(ep) },
          meta: { page: page, limit: limit, total: total }
        }
      end

      def show
        episode = current_user.episodes.find_by_prefix_id!(params[:id])

        render json: { episode: serialize_episode(episode) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Episode not found" }, status: :not_found
      end

      def create
        podcast = GetsDefaultPodcastForUser.call(user: current_user)

        result = case episode_params[:source_type]
        when "url"
          create_from_url(podcast)
        when "text"
          create_from_text(podcast)
        when "extension"
          create_from_extension(podcast)
        when "file", "email"
          return render json: { error: "source_type '#{episode_params[:source_type]}' is read-only and cannot be submitted via this API. Use 'url', 'text', or 'extension'." }, status: :unprocessable_entity
        when nil, ""
          return render json: { error: "source_type is required. Use 'url', 'text', or 'extension'." }, status: :unprocessable_entity
        else
          return render json: { error: "source_type must be 'url', 'text', or 'extension'." }, status: :unprocessable_entity
        end

        if result.success?
          RecordsEpisodeUsage.call(user: current_user)
          deduct_credit_if_needed(result.data)
          render json: { id: result.data.prefix_id }, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def destroy
        episode = current_user.episodes.find_by_prefix_id!(params[:id])
        DeleteEpisodeJob.perform_later(episode_id: episode.id)

        render json: { deleted: true }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Episode not found" }, status: :not_found
      end

      private

      def episode_params
        params.permit(:title, :author, :description, :content, :url, :source_type, :text, :voice)
      end

      def create_from_url(podcast)
        CreatesUrlEpisode.call(
          podcast: podcast,
          user: current_user,
          url: episode_params[:url]
        )
      end

      def create_from_text(podcast)
        CreatesPasteEpisode.call(
          podcast: podcast,
          user: current_user,
          text: episode_params[:text],
          title: episode_params[:title],
          author: episode_params[:author]
        )
      end

      def create_from_extension(podcast)
        CreatesExtensionEpisode.call(
          podcast: podcast,
          user: current_user,
          title: episode_params[:title],
          content: episode_params[:content],
          url: episode_params[:url],
          author: episode_params[:author],
          description: episode_params[:description]
        )
      end

      def serialize_episode(episode)
        {
          id: episode.prefix_id,
          title: episode.title,
          author: episode.author,
          description: episode.description,
          status: episode.status,
          source_type: episode.source_type,
          source_url: episode.source_url,
          audio_url: episode.audio_url,
          duration_seconds: episode.duration_seconds,
          error_message: episode.error_message,
          created_at: episode.created_at.iso8601
        }
      end

      # Free-tier users out of credits get a 402 pointing at the billing
      # upgrade URL. This is Path 1 (bearer-authenticated + credits) only —
      # MPP pay-to-create lives on /api/v1/mpp/episodes. No WWW-Authenticate
      # header and no MPP challenge are returned here; clients that want to
      # pay-per-episode must use the /mpp/* endpoints.
      def check_episode_creation_permission
        result = ChecksEpisodeCreationPermission.call(
          user: current_user,
          anticipated_cost: anticipated_cost
        )
        return if result.success?

        render json: {
          error: "Payment required",
          credits_remaining: current_user.credits_remaining,
          subscription_active: current_user.premium?,
          upgrade_url: "#{AppConfig::Domain::BASE_URL}/billing"
        }, status: :payment_required
      end

      def check_episode_rate_limit
        result = ChecksEpisodeRateLimit.call(user: current_user)
        return if result.success?

        render json: { error: result.error }, status: :too_many_requests
      end

      # URL submissions defer the debit to ProcessesUrlEpisode — the
      # article's real character count isn't known until after fetch and
      # extraction, so pricing must wait. Text/extension submissions stay
      # sync because the content is already in the request.
      def deduct_credit_if_needed(episode)
        return if current_user.complimentary? || current_user.unlimited?
        return if episode.url?

        DeductsCredit.call(user: current_user, episode: episode, cost_in_credits: anticipated_cost)
      end

      def anticipated_cost
        @anticipated_cost ||= CalculatesEpisodeCreditCost.call(
          source_text_length: source_text_length_for_cost,
          voice: voice_for_cost
        )
      end

      def source_text_length_for_cost
        case episode_params[:source_type]
        when "text"
          episode_params[:text].to_s.length
        when "extension"
          episode_params[:content].to_s.length
        when "url"
          1
        else
          0
        end
      end

      # The API permits :voice for forward-compatibility but does NOT yet
      # thread it into Creates*Episode services — synthesis always uses
      # user.voice_preference. Pricing must match what actually gets
      # rendered, otherwise a client passing voice=felix (Standard) while
      # user.voice_preference=callum (Premium) would be under-charged.
      def voice_for_cost
        Voice.find(current_user.voice_preference) || Voice.find(Voice::DEFAULT_KEY)
      end
    end
  end
end
