# frozen_string_literal: true

class EpisodesChannel < ApplicationCable::Channel
  def subscribed
    podcast = current_user.podcasts.find_by(id: params[:podcast_id])
    reject unless podcast

    stream_from stream_name

    # Broadcast current state of any in-progress episodes
    # This handles the race condition where broadcasts may have been sent
    # before the client subscribed
    broadcast_in_progress_episodes(podcast)
  end

  private

  def stream_name
    "podcast_#{params[:podcast_id]}_episodes"
  end

  def broadcast_in_progress_episodes(podcast)
    podcast.episodes.where(status: [ :pending, :processing ]).find_each do |episode|
      episode.broadcast_status_change
    end
  end
end
