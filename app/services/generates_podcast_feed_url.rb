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

    AppConfig::Storage.public_feed_url(podcast.podcast_id)
  end

  private

  attr_reader :podcast
end
