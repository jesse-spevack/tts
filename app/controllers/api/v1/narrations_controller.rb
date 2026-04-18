# frozen_string_literal: true

module Api
  module V1
    class NarrationsController < ActionController::API
      def show
        narration = Narration.find_by!(public_id: params[:public_id])

        if narration.expires_at < Time.current
          head :not_found
          return
        end

        response = {
          public_id: narration.public_id,
          status: narration.status,
          title: narration.title,
          author: narration.author,
          duration_seconds: narration.duration_seconds
        }

        if narration.complete?
          response[:audio_url] = GeneratesNarrationAudioUrl.call(narration)
        end

        render json: response
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end
    end
  end
end
