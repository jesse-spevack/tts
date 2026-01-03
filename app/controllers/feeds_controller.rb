# frozen_string_literal: true

class FeedsController < ApplicationController
  def show
    podcast_id = params[:podcast_id].delete_suffix(".xml")
    podcast = Podcast.find_by(podcast_id: podcast_id)

    return head :not_found unless podcast

    gcs_url = AppConfig::Storage.feed_url(podcast_id)
    uri = URI(gcs_url)
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      expires_in 5.minutes, public: true
      render xml: response.body, status: :ok
    else
      head :not_found
    end
  end
end
