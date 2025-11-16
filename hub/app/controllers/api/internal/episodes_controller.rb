module Api
  module Internal
    class EpisodesController < ApplicationController
      skip_before_action :require_authentication
      skip_forgery_protection
      before_action :verify_generator_secret
      before_action :set_episode

      def update
        if @episode.update(episode_params)
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

      def verify_generator_secret
        secret = request.headers["X-Generator-Secret"]
        expected = ENV.fetch("HUB_CALLBACK_SECRET", nil)

        unless expected && ActiveSupport::SecurityUtils.secure_compare(secret.to_s, expected)
          Rails.logger.warn "event=unauthorized_callback_attempt ip=#{request.remote_ip}"
          render json: { status: "error", message: "Unauthorized" }, status: :unauthorized
        end
      end
    end
  end
end
