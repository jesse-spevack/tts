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
        case episode_params[:source_type]
        when "file", "email"
          return render json: { error: "source_type '#{episode_params[:source_type]}' is read-only and cannot be submitted via this API. Use 'url', 'text', or 'extension'." }, status: :unprocessable_entity
        when nil, ""
          return render json: { error: "source_type is required. Use 'url', 'text', or 'extension'." }, status: :unprocessable_entity
        when "url", "text", "extension"
          # fall through to facade
        else
          return render json: { error: "source_type must be 'url', 'text', or 'extension'." }, status: :unprocessable_entity
        end

        result = CreatesEpisode.call(
          user: current_user,
          podcast: GetsDefaultPodcastForUser.call(user: current_user),
          source_type: episode_params[:source_type],
          params: facade_params,
          cost_in_credits: anticipated_cost
        )

        if result.success?
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

      # Shape API params into the flat hash CreatesEpisode expects. Note the
      # API intentionally does NOT forward source_url for text submissions —
      # that field is web-form-only; preserve that difference.
      def facade_params
        case episode_params[:source_type]
        when "url"
          { url: episode_params[:url] }
        when "text"
          {
            text: episode_params[:text],
            title: episode_params[:title],
            author: episode_params[:author]
          }
        when "extension"
          {
            title: episode_params[:title],
            content: episode_params[:content],
            url: episode_params[:url],
            author: episode_params[:author],
            description: episode_params[:description]
          }
        else
          {}
        end
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
          paid_user: current_user.paid?,
          upgrade_url: "#{AppConfig::Domain::BASE_URL}/billing"
        }, status: :payment_required
      end

      def check_episode_rate_limit
        result = ChecksEpisodeRateLimit.call(user: current_user)
        return if result.success?

        render json: { error: result.error }, status: :too_many_requests
      end

      # Extension submissions carry the article body in :content (not :text),
      # so we pass :content through the :text kwarg since the cost service
      # treats 'extension' as a text variant.
      def anticipated_cost
        @anticipated_cost ||= CalculatesAnticipatedEpisodeCost.call(
          EpisodeCostRequest.new(
            user: current_user,
            source_type: episode_params[:source_type],
            text: text_for_cost,
            url: episode_params[:url]
          )
        ).data.credits
      end

      def text_for_cost
        case episode_params[:source_type]
        when "extension" then episode_params[:content]
        else episode_params[:text]
        end
      end
    end
  end
end
