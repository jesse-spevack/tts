# frozen_string_literal: true

class ProcessFileEpisodeJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, user_id:, **) { user_id }

  def perform(episode_id:, user_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: user_id, action_id: action_id) do
      episode = Episode.find(episode_id)
      ProcessFileEpisode.call(episode: episode)
    end
  end
end
