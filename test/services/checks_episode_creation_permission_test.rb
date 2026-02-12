require "test_helper"

class ChecksEpisodeCreationPermissionTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @premium_user = users(:subscriber)
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

  test "returns success for free user with credits at episode limit" do
    credit_user = users(:credit_user)
    EpisodeUsage.create!(
      user: credit_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    result = ChecksEpisodeCreationPermission.call(user: credit_user)

    assert result.success?
    assert result.data[:using_credit]
  end

  test "returns success for free user with credits over episode limit" do
    credit_user = users(:credit_user)
    EpisodeUsage.create!(
      user: credit_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 5
    )

    result = ChecksEpisodeCreationPermission.call(user: credit_user)

    assert result.success?
    assert result.data[:using_credit]
  end

  test "returns failure for free user with zero credits at limit" do
    user = users(:jesse)  # has empty_balance (0 credits)
    EpisodeUsage.create!(
      user: user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    result = ChecksEpisodeCreationPermission.call(user: user)

    assert result.failure?
  end
end
