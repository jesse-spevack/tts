require "test_helper"

class EpisodeTest < ActiveSupport::TestCase
  test "validates presence of title" do
    episode = Episode.new(author: "Author", description: "Description", podcast: podcasts(:one))
    episode.valid?

    assert_includes episode.errors[:title], "can't be blank"
  end

  test "validates title length maximum" do
    episode = Episode.new(
      title: "a" * 256,
      author: "Author",
      description: "Description",
      podcast: podcasts(:one)
    )
    episode.valid?

    assert_includes episode.errors[:title], "is too long (maximum is 255 characters)"
  end

  test "validates presence of author" do
    episode = Episode.new(title: "Title", description: "Description", podcast: podcasts(:one))
    episode.valid?

    assert_includes episode.errors[:author], "can't be blank"
  end

  test "validates author length maximum" do
    episode = Episode.new(
      title: "Title",
      author: "a" * 256,
      description: "Description",
      podcast: podcasts(:one)
    )
    episode.valid?

    assert_includes episode.errors[:author], "is too long (maximum is 255 characters)"
  end

  test "validates presence of description" do
    episode = Episode.new(title: "Title", author: "Author", podcast: podcasts(:one))
    episode.valid?

    assert_includes episode.errors[:description], "can't be blank"
  end

  test "validates description length maximum" do
    episode = Episode.new(
      title: "Title",
      author: "Author",
      description: "a" * 1001,
      podcast: podcasts(:one)
    )
    episode.valid?

    assert_includes episode.errors[:description], "is too long (maximum is 1000 characters)"
  end

  test "status enum includes expected values" do
    episode = episodes(:one)

    assert_respond_to episode, :pending?
    assert_respond_to episode, :processing?
    assert_respond_to episode, :complete?
    assert_respond_to episode, :failed?
  end

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

  test "validates duration_seconds is positive" do
    episode = episodes(:one)
    episode.duration_seconds = -1
    episode.valid?

    assert_includes episode.errors[:duration_seconds], "must be greater than 0"
  end

  test "validates duration_seconds max is 24 hours" do
    episode = episodes(:one)
    episode.duration_seconds = 86_401
    episode.valid?

    assert_includes episode.errors[:duration_seconds], "must be less than or equal to 86400"
  end

  test "allows nil duration_seconds" do
    episode = episodes(:one)
    episode.duration_seconds = nil

    assert episode.valid?
  end

  test "voice delegates to user" do
    episode = episodes(:one)
    episode.user.voice_preference = "sloane"

    assert_equal "en-US-Standard-C", episode.voice
  end

  test "voice returns user default when no preference set" do
    episode = episodes(:one)
    episode.user.voice_preference = nil
    episode.user.tier = :free

    assert_equal "en-GB-Standard-D", episode.voice
  end

  test "has a prefixed id starting with ep_" do
    episode = episodes(:two)
    assert episode.prefix_id.present?
    assert episode.prefix_id.start_with?("ep_")
  end

  test "can be found by prefix_id" do
    episode = episodes(:two)
    found = Episode.find_by_prefix_id(episode.prefix_id)
    assert_equal episode, found
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
end
