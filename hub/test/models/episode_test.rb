require "test_helper"

class EpisodeTest < ActiveSupport::TestCase
  test "newest_first scope orders by created_at descending" do
    episodes(:one)
    newer_episode = Episode.create!(
      title: "Newer Episode",
      author: "Author",
      description: "Description",
      podcast: podcasts(:one),
      user: users(:one),
      status: "pending"
    )

    episodes = Episode.newest_first
    assert_equal newer_episode, episodes.first
  end

  test "audio_url returns correct URL when complete and gcs_episode_id present" do
    podcast = podcasts(:one)
    episode = Episode.create!(
      title: "Test",
      author: "Author",
      description: "Description",
      podcast: podcast,
      user: users(:one),
      status: "complete",
      gcs_episode_id: "episode_123"
    )

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    expected_url = "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast.podcast_id}/episodes/episode_123.mp3"

    assert_equal expected_url, episode.audio_url
  end

  test "audio_url returns nil when status is not complete" do
    episode = Episode.new(
      title: "Test",
      author: "Author",
      description: "Description",
      podcast: podcasts(:one),
      status: "pending",
      gcs_episode_id: "episode_123"
    )

    assert_nil episode.audio_url
  end

  test "audio_url returns nil when gcs_episode_id is blank" do
    episode = Episode.new(
      title: "Test",
      author: "Author",
      description: "Description",
      podcast: podcasts(:one),
      status: "complete",
      gcs_episode_id: nil
    )

    assert_nil episode.audio_url
  end

  test "soft_delete! sets deleted_at to current time" do
    episode = episodes(:one)
    assert_nil episode.deleted_at

    freeze_time do
      episode.soft_delete!
      assert_equal Time.current, episode.deleted_at
    end
  end

  test "default scope excludes soft-deleted episodes" do
    episode = episodes(:one)
    episode.soft_delete!

    assert_not_includes Episode.all, episode
  end

  test "soft-deleted episode still exists in database" do
    episode = episodes(:one)
    episode.soft_delete!

    assert Episode.unscoped.exists?(episode.id)
  end

  test "soft_delete! raises if already deleted" do
    episode = episodes(:one)
    episode.soft_delete!

    assert_raises(RuntimeError, "Episode already deleted") do
      Episode.unscoped.find(episode.id).soft_delete!
    end
  end

  test "soft_deleted? returns false for non-deleted episode" do
    episode = episodes(:one)
    assert_not episode.soft_deleted?
  end

  test "soft_deleted? returns true for deleted episode" do
    episode = episodes(:one)
    episode.soft_delete!

    assert Episode.unscoped.find(episode.id).soft_deleted?
  end
end
