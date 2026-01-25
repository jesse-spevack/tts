module Api
  module V1
    class EpisodesController < BaseController
      before_action :check_episode_creation_permission

      def create
        podcast = GetsDefaultPodcastForUser.call(user: current_user)

        result = CreatesExtensionEpisode.call(
          podcast: podcast,
          user: current_user,
          title: episode_params[:title],
          content: episode_params[:content],
          url: episode_params[:url],
          author: episode_params[:author],
          description: episode_params[:description]
        )

        if result.success?
          RecordsEpisodeUsage.call(user: current_user)
          render json: { id: result.data.prefix_id }, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      private

      def episode_params
        params.permit(:title, :author, :description, :content, :url)
      end

      def check_episode_creation_permission
        result = ChecksEpisodeCreationPermission.call(user: current_user)
        return if result.success?

        render json: { error: "Episode limit reached. Please upgrade your plan." }, status: :forbidden
      end
    end
  end
end
