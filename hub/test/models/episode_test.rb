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
end
