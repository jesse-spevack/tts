require "test_helper"

class CanCreateEpisodeTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @premium_user = users(:premium_user)
    @unlimited_user = users(:unlimited_user)
  end

  test "returns allowed for premium user" do
    result = CanCreateEpisode.call(user: @premium_user)

    assert result.allowed?
    assert_not result.denied?
    assert_nil result.remaining
  end

  test "returns allowed for unlimited user" do
    result = CanCreateEpisode.call(user: @unlimited_user)

    assert result.allowed?
    assert_nil result.remaining
  end

  test "returns allowed with remaining count for free user with no usage" do
    result = CanCreateEpisode.call(user: @free_user)

    assert result.allowed?
    assert_equal 2, result.remaining
  end

  test "returns allowed with remaining count for free user with 1 episode" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 1
    )

    result = CanCreateEpisode.call(user: @free_user)

    assert result.allowed?
    assert_equal 1, result.remaining
  end

  test "returns denied for free user at limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    result = CanCreateEpisode.call(user: @free_user)

    assert result.denied?
    assert_not result.allowed?
    assert_equal 0, result.remaining
  end

  test "returns denied for free user over limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 3
    )

    result = CanCreateEpisode.call(user: @free_user)

    assert result.denied?
  end

  test "only counts current month usage" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: 1.month.ago.beginning_of_month.to_date,
      episode_count: 5
    )

    result = CanCreateEpisode.call(user: @free_user)

    assert result.allowed?
    assert_equal 2, result.remaining
  end
end
