# frozen_string_literal: true

class DeleteEpisodeJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default

  def perform(episode_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: nil, action_id: action_id) do
      episode = Episode.unscoped.find(episode_id)
      DeletesEpisode.call(episode: episode)
    end
  end
end
