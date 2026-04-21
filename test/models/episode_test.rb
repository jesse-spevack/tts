# frozen_string_literal: true

require "test_helper"

class EpisodeTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

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

  test "does not broadcast on title change alone" do
    episode = episodes(:one)
    episode.update!(status: :processing)

    assert_no_broadcasts("podcast_#{episode.podcast_id}_episodes") do
      episode.update!(title: "Updated Title From URL")
    end
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

  test "after_update_commit broadcasts when status changes" do
    episode = episodes(:one)
    episode.update!(status: :processing)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_broadcasts(stream_name, 1) do
      episode.update!(status: :complete, gcs_episode_id: "ep_123")
    end
  end

  test "after_update_commit does not broadcast when only title changes" do
    episode = episodes(:one)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_no_broadcasts(stream_name) do
      episode.update!(title: "Updated Title")
    end
  end

  test "after_update_commit broadcasts when status changes to preparing" do
    episode = episodes(:one)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_broadcasts(stream_name, 1) do
      episode.update!(status: :preparing)
    end
  end

  test "after_update_commit does not broadcast when status and title unchanged" do
    episode = episodes(:one)
    stream_name = "podcast_#{episode.podcast_id}_episodes"

    assert_no_broadcasts(stream_name) do
      episode.update!(description: "Updated description")
    end
  end

  # --- episodes.voice is its own attribute (agent-team-cue3) ---
  #
  # Episode previously delegated #voice to the owning User. After cue3,
  # Episode has its own voice column and #voice reads that attribute
  # directly. No delegation: episode.voice must be independent of
  # user.voice_preference / user.voice.

  test "Episode#voice returns the stored attribute, not a delegated user voice" do
    # Episode owns a voice column now, so setting voice on a new record
    # must round-trip through the attribute — no delegate, no user required.
    episode = Episode.new(voice: "some-explicit-voice")
    assert_equal "some-explicit-voice", episode.voice
  end

  test "Episode#voice is independent of user.voice_preference" do
    user = users(:jesse)
    user.update!(voice_preference: "callum")

    episode = Episode.new(user: user, voice: nil)

    # Before cue3, this would delegate through user.voice and return a
    # google voice string. After cue3, episode.voice is its own column
    # and must return nil when nothing was stamped.
    assert_nil episode.voice
  end

  test "Episode#voice ignores later changes to user.voice_preference" do
    user = users(:jesse)
    episode = Episode.create!(
      podcast: podcasts(:one),
      user: user,
      title: "Test",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/test",
      status: :complete,
      voice: Voice::DEFAULT_STANDARD
    )

    # User changes their preference to a Premium voice — episode's stamped
    # voice must not move. If the delegate were still in place, episode.voice
    # would follow user.voice and this would fail.
    user.update!(voice_preference: "callum")

    assert_equal Voice::DEFAULT_STANDARD, episode.reload.voice
  end
end
