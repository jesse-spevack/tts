require "test_helper"

class RecordEpisodeUsageTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @premium_user = users(:premium_user)
  end

  test "creates usage record and increments for free user" do
    assert_difference "EpisodeUsage.count", 1 do
      RecordEpisodeUsage.call(user: @free_user)
    end

    usage = EpisodeUsage.current_for(@free_user)
    assert_equal 1, usage.episode_count
  end

  test "increments existing usage record for free user" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 1
    )

    assert_no_difference "EpisodeUsage.count" do
      RecordEpisodeUsage.call(user: @free_user)
    end

    usage = EpisodeUsage.current_for(@free_user)
    assert_equal 2, usage.episode_count
  end

  test "does nothing for premium user" do
    assert_no_difference "EpisodeUsage.count" do
      RecordEpisodeUsage.call(user: @premium_user)
    end
  end

  test "does nothing for unlimited user" do
    unlimited_user = users(:unlimited_user)

    assert_no_difference "EpisodeUsage.count" do
      RecordEpisodeUsage.call(user: unlimited_user)
    end
  end
end
