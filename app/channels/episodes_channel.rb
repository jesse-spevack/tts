# frozen_string_literal: true

class EpisodesChannel < ApplicationCable::Channel
  def subscribed
    podcast = current_user.podcasts.find_by(id: params[:podcast_id])
    reject unless podcast

    stream_from stream_name

    # Broadcast current state of episodes that may have changed during page load.
    # This handles the race condition where status broadcasts may have been sent
    # before the WebSocket subscription was established.
    broadcast_recently_changed_episodes(podcast)
  end

  private

  def stream_name
    "podcast_#{params[:podcast_id]}_episodes"
  end

  def broadcast_recently_changed_episodes(podcast)
    # Broadcast episodes still in progress OR recently updated (within 30 seconds).
    # The 30-second window covers the race condition where an episode changes
    # status between page render and WebSocket connection.
    podcast.episodes
      .where(status: [ :pending, :processing ])
      .or(podcast.episodes.where(updated_at: 30.seconds.ago..))
      .find_each do |episode|
        episode.broadcast_status_change
      end
  end
end
