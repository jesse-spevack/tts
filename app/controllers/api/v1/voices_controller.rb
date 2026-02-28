module Api
  module V1
    class VoicesController < BaseController
      def index
        voice_keys = current_user.available_voices

        voices = voice_keys.map do |key|
          data = Voice.find(key)
          {
            id: key,
            name: data[:name],
            accent: data[:accent],
            gender: data[:gender]
          }
        end

        render json: { voices: voices }
      end
    end
  end
end
