# frozen_string_literal: true

class EpisodesChannel < ApplicationCable::Channel
  def subscribed
    podcast = current_user.podcasts.find_by(id: params[:podcast_id])

    if podcast
      stream_from stream_name
      broadcast_recently_changed_episodes(podcast)
    else
      reject
    end
  end

  private

  def stream_name
    "podcast_#{params[:podcast_id]}_episodes"
  end

  def broadcast_recently_changed_episodes(podcast)
    FindsRecentlyChangedEpisodes.call(podcast: podcast).find_each do |episode|
      episode.broadcast_status_change
    end
  end
end
