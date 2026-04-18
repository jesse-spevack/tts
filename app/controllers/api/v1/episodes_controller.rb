module Api
  module V1
    class EpisodesController < BaseController
      include MppPayable

      before_action :check_episode_creation_permission, only: [ :create ]
      before_action :check_episode_rate_limit, only: [ :create ]

      def index
        episodes = current_user.episodes.newest_first
        page = (params[:page] || 1).to_i
        limit = [ (params[:limit] || AppConfig::Api::DEFAULT_PER_PAGE).to_i, AppConfig::Api::MAX_PER_PAGE ].min

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
        else
          return render json: { error: "source_type is required. Use 'url', 'text', or 'extension'." }, status: :unprocessable_entity
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
          duration_seconds: episode.duration_seconds,
          error_message: episode.error_message,
          created_at: episode.created_at.iso8601
        }
      end

      def check_episode_creation_permission
        result = ChecksEpisodeCreationPermission.call(user: current_user)
        return if result.success?

        render json: { error: "Episode limit reached. Please upgrade your plan." }, status: :forbidden
      end

      def check_episode_rate_limit
        result = ChecksEpisodeRateLimit.call(user: current_user)
        return if result.success?

        render json: { error: result.error }, status: :too_many_requests
      end

      def deduct_credit_if_needed(episode)
        return unless current_user.credit_user?

        DeductsCredit.call(user: current_user, episode: episode)
      end
    end
  end
end
