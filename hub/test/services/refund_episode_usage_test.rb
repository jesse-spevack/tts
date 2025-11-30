require "test_helper"

class RefundEpisodeUsageTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @premium_user = users(:premium_user)
  end

  test "decrements usage record for free user" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    RefundEpisodeUsage.call(user: @free_user)

    usage = EpisodeUsage.current_for(@free_user)
    assert_equal 1, usage.episode_count
  end

  test "does not go below zero" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 0
    )

    RefundEpisodeUsage.call(user: @free_user)

    usage = EpisodeUsage.current_for(@free_user)
    assert_equal 0, usage.episode_count
  end

  test "does nothing if no usage record exists" do
    assert_no_difference "EpisodeUsage.count" do
      RefundEpisodeUsage.call(user: @free_user)
    end
  end

  test "does nothing for premium user" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    RefundEpisodeUsage.call(user: @premium_user)

    # Free user's count should be unchanged
    usage = EpisodeUsage.current_for(@free_user)
    assert_equal 2, usage.episode_count
  end

  test "does nothing for unlimited user" do
    unlimited_user = users(:unlimited_user)

    assert_no_difference "EpisodeUsage.count" do
      RefundEpisodeUsage.call(user: unlimited_user)
    end
  end
end
