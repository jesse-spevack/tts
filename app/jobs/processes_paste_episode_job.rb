# frozen_string_literal: true

class ProcessesPasteEpisodeJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, user_id:, **) { user_id }

  def perform(episode_id:, user_id:, action_id: nil, voice_override: nil)
    with_episode_logging(episode_id: episode_id, user_id: user_id, action_id: action_id) do
      episode = Episode.find(episode_id)
      next if skip_if_user_deactivated?(episode)

      ProcessesPasteEpisode.call(episode: episode, voice_override: voice_override)
    end
  end
end
