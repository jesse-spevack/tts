class ProcessUrlEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    episode = Episode.find(episode_id)
    ProcessUrlEpisode.call(episode: episode)
  end
end
