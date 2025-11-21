module Api
  module Internal
    class EpisodesController < BaseController
      before_action :set_episode

      def update
        if @episode.update(episode_params)
          ReleaseFreeEpisodeClaim.call(episode: @episode) if @episode.failed?
          Rails.logger.info "event=episode_callback_received episode_id=#{@episode.id} status=#{@episode.status}"
          render json: { status: "success" }
        else
          render json: { status: "error", errors: @episode.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ArgumentError => e
        render json: { status: "error", message: e.message }, status: :unprocessable_entity
      end

      private

      def set_episode
        @episode = Episode.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { status: "error", message: "Episode not found" }, status: :not_found
      end

      def episode_params
        params.permit(:status, :gcs_episode_id, :audio_size_bytes, :error_message)
      end
    end
  end
end
