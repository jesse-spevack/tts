require "test_helper"

class ChecksEpisodeCreationPermissionTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @premium_user = users(:premium_user)
    @unlimited_user = users(:unlimited_user)
  end

  test "returns success for premium user" do
    result = ChecksEpisodeCreationPermission.call(user: @premium_user)

    assert result.success?
    refute result.failure?
    assert_nil result.data
  end

  test "returns success for unlimited user" do
    result = ChecksEpisodeCreationPermission.call(user: @unlimited_user)

    assert result.success?
    assert_nil result.data
  end

  test "returns success with remaining count for free user with no usage" do
    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.success?
    assert_equal 2, result.data[:remaining]
  end

  test "returns success with remaining count for free user with 1 episode" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 1
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.success?
    assert_equal 1, result.data[:remaining]
  end

  test "returns failure for free user at limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.failure?
    refute result.success?
    assert_equal "Episode limit reached", result.message
  end

  test "returns failure for free user over limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 3
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.failure?
  end

  test "only counts current month usage" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: 1.month.ago.beginning_of_month.to_date,
      episode_count: 5
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.success?
    assert_equal 2, result.data[:remaining]
  end
end
