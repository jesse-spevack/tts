require "test_helper"

class EpisodeUsageTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "belongs to user" do
    usage = EpisodeUsage.new(user: @user, period_start: Date.current.beginning_of_month)
    assert_equal @user, usage.user
  end

  test "requires period_start" do
    usage = EpisodeUsage.new(user: @user, period_start: nil)
    assert_not usage.valid?
    assert_includes usage.errors[:period_start], "can't be blank"
  end

  test "requires episode_count to be non-negative" do
    usage = EpisodeUsage.new(user: @user, period_start: Date.current, episode_count: -1)
    assert_not usage.valid?
    assert_includes usage.errors[:episode_count], "must be greater than or equal to 0"
  end

  test "current_for returns existing record for current month" do
    period = Time.current.beginning_of_month.to_date
    existing = EpisodeUsage.create!(user: @user, period_start: period, episode_count: 1)

    result = EpisodeUsage.current_for(@user)

    assert_equal existing, result
    assert result.persisted?
  end

  test "current_for initializes new record if none exists" do
    result = EpisodeUsage.current_for(@user)

    assert_not result.persisted?
    assert_equal @user, result.user
    assert_equal Time.current.beginning_of_month.to_date, result.period_start
  end

  test "increment! increases episode_count by 1" do
    usage = EpisodeUsage.create!(user: @user, period_start: Date.current, episode_count: 0)

    usage.increment!

    assert_equal 1, usage.reload.episode_count
  end

  test "decrement! decreases episode_count by 1" do
    usage = EpisodeUsage.create!(user: @user, period_start: Date.current, episode_count: 2)

    usage.decrement!

    assert_equal 1, usage.reload.episode_count
  end

  test "decrement! does not go below 0" do
    usage = EpisodeUsage.create!(user: @user, period_start: Date.current, episode_count: 0)

    usage.decrement!

    assert_equal 0, usage.reload.episode_count
  end

  test "unique constraint on user_id and period_start" do
    period = Date.current.beginning_of_month
    EpisodeUsage.create!(user: @user, period_start: period)

    duplicate = EpisodeUsage.new(user: @user, period_start: period)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end
end
