# frozen_string_literal: true

class FeedsController < ApplicationController
  allow_unauthenticated_access

  def show
    podcast_id = params[:podcast_id].delete_suffix(".xml")
    podcast = Podcast.find_by(podcast_id: podcast_id)

    return head :not_found unless podcast

    feed_content = CloudStorage.new(podcast_id: podcast_id).download_file(remote_path: "feed.xml")
    expires_in 5.minutes, public: true
    render xml: feed_content, status: :ok
  rescue StandardError => e
    Rails.logger.warn("Feed fetch failed for podcast #{podcast_id}: #{e.message}")
    head :not_found
  end
end
