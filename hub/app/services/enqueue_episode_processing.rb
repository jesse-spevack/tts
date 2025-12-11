# frozen_string_literal: true

class EnqueueEpisodeProcessing
  def self.call(episode:, staging_path:)
    new(episode: episode, staging_path: staging_path).call
  end

  def initialize(episode:, staging_path:)
    @episode = episode
    @staging_path = staging_path
  end

  def call
    tasks_enqueuer.enqueue_episode_processing(
      episode_id: episode.id,
      podcast_id: episode.podcast.podcast_id,
      staging_path: staging_path,
      metadata: {
        title: episode.title,
        author: episode.author,
        description: episode.description
      },
      voice_name: episode.voice
    )
  end

  private

  attr_reader :episode, :staging_path

  def tasks_enqueuer
    @tasks_enqueuer ||= CloudTasksEnqueuer.new
  end
end
