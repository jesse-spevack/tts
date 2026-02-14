# frozen_string_literal: true

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
      source_type: :url,
      source_url: "https://example.com/test",
      status: :pending
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
      source_type: :url,
      source_url: "https://example.com/test",
      status: :complete,
      gcs_episode_id: "episode_123"
    )

    expected_url = "https://storage.googleapis.com/#{AppConfig::Storage::BUCKET}/podcasts/#{podcast.podcast_id}/episodes/episode_123.mp3"

    assert_equal expected_url, episode.audio_url
  end

  test "audio_url returns nil when status is not complete" do
    episode = Episode.new(
      title: "Test",
      author: "Author",
      description: "Description",
      podcast: podcasts(:one),
      status: :pending,
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
      status: :complete,
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

  test "paste episode requires source_text presence" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: nil,
      status: :processing
    )

    assert_not episode.valid?
    assert_includes episode.errors[:source_text], "cannot be empty"
  end

  test "file episode requires source_text presence" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :file,
      source_text: "",
      status: :processing
    )

    assert_not episode.valid?
    assert_includes episode.errors[:source_text], "cannot be empty"
  end

  test "url episode does not require source_text" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/article",
      source_text: nil,
      status: :processing
    )

    assert episode.valid?
  end

  test "paste episode requires minimum 100 characters" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: "A" * 99,
      status: :processing
    )

    assert_not episode.valid?
    assert episode.errors[:source_text].first.include?("at least 100 characters")
  end

  test "paste episode accepts exactly 100 characters" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: "A" * 100,
      status: :processing
    )

    assert episode.valid?
  end

  test "file episode requires minimum 100 characters" do
    episode = Episode.new(
      podcast: podcasts(:one),
      user: users(:one),
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :file,
      source_text: "short",
      status: :processing
    )

    assert_not episode.valid?
    assert episode.errors[:source_text].first.include?("at least 100 characters")
  end

  test "paste episode validates tier character limit" do
    user = users(:free_user)
    max_chars = user.character_limit

    episode = Episode.new(
      podcast: podcasts(:one),
      user: user,
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: "A" * (max_chars + 1),
      status: :processing
    )

    assert_not episode.valid?
    assert episode.errors[:source_text].first.include?("exceeds your plan's")
  end

  test "paste episode accepts content at tier limit" do
    user = users(:free_user)
    max_chars = user.character_limit

    episode = Episode.new(
      podcast: podcasts(:one),
      user: user,
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: "A" * max_chars,
      status: :processing
    )

    assert episode.valid?
  end

  test "unlimited tier has no character limit" do
    user = users(:unlimited_user)

    episode = Episode.new(
      podcast: podcasts(:one),
      user: user,
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :paste,
      source_text: "A" * 100_000,
      status: :processing
    )

    assert episode.valid?
  end

  test "broadcast_status_change broadcasts to the raw stream name" do
    episode = episodes(:one)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_broadcasts(stream_name, 1) do
      episode.broadcast_status_change
    end
  end

  test "broadcast_status_change sends turbo stream replace HTML" do
    episode = episodes(:one)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    episode.broadcast_status_change

    broadcasts = ActionCable.server.broadcasts(stream_name)
    assert_equal 1, broadcasts.size
    assert_includes broadcasts.first, "<turbo-stream action=\"replace\""
    assert_includes broadcasts.first, "target=\"episode_#{episode.id}\""
  end

  test "after_update_commit broadcasts when status changes" do
    episode = episodes(:one)
    episode.update!(status: :processing)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_broadcasts(stream_name, 1) do
      episode.update!(status: :complete, gcs_episode_id: "ep_123")
    end
  end

  test "after_update_commit does not broadcast when status unchanged" do
    episode = episodes(:one)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_no_broadcasts(stream_name) do
      episode.update!(title: "Updated Title")
    end
  end
end
