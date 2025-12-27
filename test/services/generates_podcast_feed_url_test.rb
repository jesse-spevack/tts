# frozen_string_literal: true

require "test_helper"

class GeneratesPodcastFeedUrlTest < ActiveSupport::TestCase
  test "returns nil when podcast_id is blank" do
    podcast = Podcast.new(podcast_id: nil)

    result = GeneratesPodcastFeedUrl.call(podcast)

    assert_nil result
  end

  test "returns feed URL for podcast with podcast_id" do
    podcast = podcasts(:default)

    result = GeneratesPodcastFeedUrl.call(podcast)

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    expected = "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast.podcast_id}/feed.xml"
    assert_equal expected, result
  end
end
