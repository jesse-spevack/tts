# frozen_string_literal: true

class GeneratesEpisodeAudioUrl
  def self.call(episode)
    new(episode).call
  end

  def initialize(episode)
    @episode = episode
  end

  def call
    return nil unless episode.complete? && episode.gcs_episode_id.present?

    AppConfig::Storage.episode_audio_url(episode.podcast.podcast_id, episode.gcs_episode_id)
  end

  private

  attr_reader :episode
end
