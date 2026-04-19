# frozen_string_literal: true

module Api
  module V1
    class NarrationsController < ActionController::API
      def show
        narration = Narration.find_by_prefix_id!(params[:id])

        if narration.expired?
          head :not_found
          return
        end

        response = {
          id: narration.prefix_id,
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
