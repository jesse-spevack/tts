module Api
  module V1
    class FeedsController < BaseController
      def show
        podcast = current_user.primary_podcast
        return render json: { error: "No podcast found" }, status: :not_found unless podcast

        render json: { feed_url: podcast.feed_url }
      end
    end
  end
end
