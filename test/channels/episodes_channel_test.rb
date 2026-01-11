# frozen_string_literal: true

require "test_helper"

class EpisodesChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    stub_connection current_user: @user
  end

  test "subscribes to podcast the user owns" do
    subscribe podcast_id: @podcast.id

    assert subscription.confirmed?
    assert_has_stream "podcast_#{@podcast.id}_episodes"
  end

  test "rejects subscription for podcast user does not own" do
    other_podcast = podcasts(:two)

    subscribe podcast_id: other_podcast.id

    assert subscription.rejected?
  end

  test "rejects subscription with invalid podcast_id" do
    subscribe podcast_id: "nonexistent"

    assert subscription.rejected?
  end

  test "rejects subscription with nil podcast_id" do
    subscribe podcast_id: nil

    assert subscription.rejected?
  end

  test "broadcasts recently changed episodes on subscription" do
    # Set all fixture episodes to complete and old to isolate our test
    @podcast.episodes.update_all(status: :complete, updated_at: 1.hour.ago)

    # Create a processing episode that should be broadcast
    episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Test Processing Episode",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/test",
      status: :processing
    )

    subscribe podcast_id: @podcast.id

    assert subscription.confirmed?
    assert_broadcasts "podcast_#{@podcast.id}_episodes", 1
  end

  test "does not broadcast completed episodes outside time window" do
    # Set all fixture episodes to complete and old
    @podcast.episodes.update_all(status: :complete, updated_at: 1.hour.ago)

    subscribe podcast_id: @podcast.id

    assert subscription.confirmed?
    assert_broadcasts "podcast_#{@podcast.id}_episodes", 0
  end

  test "does not broadcast episodes from other podcasts" do
    other_podcast = podcasts(:two)
    other_user = users(:two)
    stub_connection current_user: other_user

    # Set all episodes to old/complete
    Episode.update_all(status: :complete, updated_at: 1.hour.ago)

    # Create a processing episode on podcast :one (not owned by other_user)
    Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Test Episode",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/test",
      status: :processing
    )

    subscribe podcast_id: other_podcast.id

    assert subscription.confirmed?
    # Should not broadcast the episode from @podcast
    assert_broadcasts "podcast_#{other_podcast.id}_episodes", 0
  end
end
