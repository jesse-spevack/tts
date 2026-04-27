module Api
  module Internal
    class EpisodesController < BaseController
      before_action :set_episode

      def update
        if @episode.update(episode_params)
          # Gate on saved_change_to_status? so a no-op status update (episode
          # already :failed when the webhook re-fires) does not trigger a
          # second RefundsPayment. Without the gate, free-tier users would
          # see EpisodeUsage decremented twice — credit/MPP refunds have
          # their own idempotency, but EpisodeUsage#decrement! does not.
          RefundsPayment.call(content: @episode) if @episode.failed? && @episode.saved_change_to_status?
          notify_completion if @episode.complete?
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
        params.permit(:status, :gcs_episode_id, :audio_size_bytes, :duration_seconds, :error_message)
      end

      def notify_completion
        NotifiesEpisodeCompletion.call(episode: @episode)
      rescue StandardError => e
        Rails.logger.error "event=episode_notification_failed episode_id=#{@episode.id} error=#{e.message}"
      end
    end
  end
end
