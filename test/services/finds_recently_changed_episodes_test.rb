# frozen_string_literal: true

require "test_helper"

class FindsRecentlyChangedEpisodesTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:one)
    @user = users(:one)
  end

  test "returns episodes with pending status" do
    episode = create_episode(status: :pending, updated_at: 1.hour.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_includes result, episode
  end

  test "returns episodes with processing status" do
    episode = create_episode(status: :processing, updated_at: 1.hour.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_includes result, episode
  end

  test "returns completed episodes updated within window" do
    episode = create_episode(status: :complete, updated_at: 10.seconds.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_includes result, episode
  end

  test "returns failed episodes updated within window" do
    episode = create_episode(status: :failed, updated_at: 10.seconds.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_includes result, episode
  end

  test "excludes completed episodes updated outside window" do
    episode = create_episode(status: :complete, updated_at: 1.minute.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_not_includes result, episode
  end

  test "excludes failed episodes updated outside window" do
    episode = create_episode(status: :failed, updated_at: 1.minute.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_not_includes result, episode
  end

  test "respects custom window parameter" do
    episode = create_episode(status: :complete, updated_at: 2.minutes.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast, window: 5.minutes)

    assert_includes result, episode
  end

  test "excludes episodes from other podcasts" do
    other_podcast = podcasts(:two)
    other_episode = episodes(:two)
    other_episode.update_column(:updated_at, 10.seconds.ago)

    result = FindsRecentlyChangedEpisodes.call(podcast: @podcast)

    assert_not_includes result, other_episode
  end

  private

  def create_episode(status:, updated_at:)
    episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Test Episode #{SecureRandom.hex(4)}",
      author: "Author",
      description: "Description",
      source_type: :url,
      source_url: "https://example.com/test-article",
      status: status
    )
    episode.update_column(:updated_at, updated_at)
    episode
  end
end
