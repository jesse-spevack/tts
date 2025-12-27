# frozen_string_literal: true

require "test_helper"

class GeneratesEpisodeAudioUrlTest < ActiveSupport::TestCase
  test "returns nil when episode is not complete" do
    episode = episodes(:pending)

    result = GeneratesEpisodeAudioUrl.call(episode)

    assert_nil result
  end

  test "returns nil when gcs_episode_id is nil" do
    episode = episodes(:complete)
    episode.update!(gcs_episode_id: nil)

    result = GeneratesEpisodeAudioUrl.call(episode)

    assert_nil result
  end

  test "returns audio URL for complete episode with gcs_episode_id" do
    episode = episodes(:complete)
    episode.update!(gcs_episode_id: "abc123")

    result = GeneratesEpisodeAudioUrl.call(episode)

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    expected = "https://storage.googleapis.com/#{bucket}/podcasts/#{episode.podcast.podcast_id}/episodes/abc123.mp3"
    assert_equal expected, result
  end
end
