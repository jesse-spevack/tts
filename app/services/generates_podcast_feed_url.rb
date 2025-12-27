# frozen_string_literal: true

class GeneratesPodcastFeedUrl
  def self.call(podcast)
    new(podcast).call
  end

  def initialize(podcast)
    @podcast = podcast
  end

  def call
    return nil unless podcast.podcast_id.present?

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast.podcast_id}/feed.xml"
  end

  private

  attr_reader :podcast
end
