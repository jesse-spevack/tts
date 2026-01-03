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

    expected = "https://tts.verynormal.dev/feeds/#{podcast.podcast_id}.xml"
    assert_equal expected, result
  end
end
