module Api
  module V1
    class VoicesController < BaseController
      def index
        voices = current_user.available_voices.map do |key|
          voice = Voice.find(key)
          {
            id: voice.key,
            name: voice.name,
            accent: voice.accent,
            gender: voice.gender
          }
        end

        render json: { voices: voices }
      end
    end
  end
end
