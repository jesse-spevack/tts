# frozen_string_literal: true

require "test_helper"

class ChecksEpisodeRateLimitTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # Clear any existing episodes so we have a clean slate for rate limit tests
    @user.episodes.unscoped.delete_all
  end

  test "returns success when user has no episodes" do
    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.success?
    assert_equal 20, result.data[:remaining]
  end

  test "returns success when user is under limit" do
    create_recent_episodes(19)

    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.success?
    assert_equal 1, result.data[:remaining]
  end

  test "returns failure when user is at limit" do
    create_recent_episodes(20)

    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.failure?
    assert_equal "You've reached your hourly episode limit", result.error
  end

  test "returns failure when user is over limit" do
    create_recent_episodes(25)

    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.failure?
  end

  test "does not count episodes older than 1 hour" do
    # Create episodes outside the rate limit window
    travel_to 2.hours.ago do
      create_recent_episodes(20)
    end

    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.success?
    assert_equal 20, result.data[:remaining]
  end

  test "counts episodes from exactly 1 hour ago" do
    travel_to 59.minutes.ago do
      create_recent_episodes(20)
    end

    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.failure?
  end

  test "only counts episodes for the specified user" do
    other_user = users(:two)
    create_recent_episodes(20, user: other_user)

    result = ChecksEpisodeRateLimit.call(user: @user)

    assert result.success?
    assert_equal 20, result.data[:remaining]
  end

  test "applies to all user types including premium" do
    premium_user = users(:subscriber)
    create_recent_episodes(20, user: premium_user)

    result = ChecksEpisodeRateLimit.call(user: premium_user)

    assert result.failure?
  end

  private

  def create_recent_episodes(count, user: @user)
    podcast = user.podcasts.first || CreatesDefaultPodcast.call(user: user)

    count.times do |i|
      Episode.create!(
        user: user,
        podcast: podcast,
        title: "Rate limit test episode #{i}",
        author: "Test Author",
        description: "Test description",
        source_type: :url,
        source_url: "https://example.com/article-#{i}",
        status: :pending
      )
    end
  end
end
