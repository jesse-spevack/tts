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

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    podcast_id = episode.podcast.podcast_id
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/episodes/#{episode.gcs_episode_id}.mp3"
  end

  private

  attr_reader :episode
end
