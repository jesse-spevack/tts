require "test_helper"

class BuildsAdminMetricsReportTest < ActiveSupport::TestCase
  # Each test adds its own non-internal users/episodes on top of fixtures, then
  # asserts on deltas (post - pre) so fixture noise can't break the assertions.
  # We mark fixture-created noise as internal where needed by asserting deltas
  # against the test-only user_ids we create below.

  setup do
    @podcast = Podcast.create!(podcast_id: "pod_test_metrics_#{SecureRandom.hex(4)}", title: "Metrics", description: "")
  end

  def make_user(email, created_at:, internal: false)
    User.create!(
      email_address: email,
      account_type: :standard,
      internal: internal,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def make_episode(user, created_at:, status: "complete")
    episode = Episode.new(
      podcast: @podcast,
      user: user,
      title: "t",
      author: "a",
      description: "d",
      source_type: :paste,
      source_text: "some text content" * 20,
      status: status
    )
    episode.save!(validate: false)
    episode.update_columns(created_at: created_at, updated_at: created_at)
    episode
  end

  # ----------------------- Activation -----------------------

  test "activation counts new signups in last 7 and 30 days, excluding internal" do
    before = BuildsAdminMetricsReport.call.activation

    make_user("m1_a@example.com", created_at: 2.days.ago)
    make_user("m1_b@example.com", created_at: 20.days.ago)
    make_user("m1_c@example.com", created_at: 40.days.ago)
    make_user("m1_internal@example.com", created_at: 1.day.ago, internal: true)

    after = BuildsAdminMetricsReport.call.activation

    assert_equal 1, after[:signups_7d] - before[:signups_7d]
    assert_equal 2, after[:signups_30d] - before[:signups_30d]
  end

  test "activation rate counts episodes within 7 days of signup" do
    signup_time = 10.days.ago
    activated = make_user("m2_activated@example.com", created_at: signup_time)
    make_episode(activated, created_at: signup_time + 2.days)

    late_activated = make_user("m2_late@example.com", created_at: signup_time)
    make_episode(late_activated, created_at: signup_time + 10.days)

    make_user("m2_never@example.com", created_at: signup_time)

    # internal user with an episode — excluded from cohort
    internal_user = make_user("m2_internal@example.com", created_at: signup_time, internal: true)
    make_episode(internal_user, created_at: signup_time + 1.day)

    report = BuildsAdminMetricsReport.call.activation

    # We can't assert absolute, but we know:
    # - cohort_size_30d grew by 3 (non-internal users in last 30d)
    # - activated_30d grew by 1 (only `activated` was activated within 7d)
    assert_operator report[:cohort_size_30d], :>=, 3
    assert_operator report[:activated_30d], :>=, 1
    # Rate is a fraction, compute it and sanity check
    assert_in_delta((report[:activated_30d].to_f / report[:cohort_size_30d] * 100).round(2),
                    report[:activation_rate_30d], 0.01)
  end

  # ----------------------- Cohort retention -----------------------

  test "cohort retention grid returns one row per signup week with cohort_size and relative-week activity" do
    # Pick a fixed week in the past (within the 12-week window).
    anchor = 8.weeks.ago.beginning_of_week

    u1 = make_user("m3_u1@example.com", created_at: anchor + 1.day)
    u2 = make_user("m3_u2@example.com", created_at: anchor + 2.days)

    # u1 active in week +1 and week +2
    make_episode(u1, created_at: anchor + 1.week + 2.days)
    make_episode(u1, created_at: anchor + 2.weeks + 1.day)

    # u2 active in week +4 only
    make_episode(u2, created_at: anchor + 4.weeks + 3.days)

    # Internal user in the same cohort — must be excluded
    internal_user = make_user("m3_internal@example.com", created_at: anchor + 1.day, internal: true)
    make_episode(internal_user, created_at: anchor + 1.week + 1.day)

    report = BuildsAdminMetricsReport.call

    row = report.cohort_retention.find { |r| r[:week_start] == anchor.to_date }
    assert_not_nil row, "expected a cohort row for the anchor week"
    # Fixture users may share a cohort week if created_at is current-time, but
    # we explicitly anchored 8 weeks ago, so only our 2 non-internal users match.
    assert_equal 2, row[:cohort_size]
    assert_equal 1, row[:active_week_1]
    assert_equal 1, row[:active_week_2]
    assert_equal 1, row[:active_week_4]
  end

  test "cohort retention does not count internal users in cohort_size" do
    anchor = 7.weeks.ago.beginning_of_week

    before = BuildsAdminMetricsReport.call.cohort_retention.find { |r| r[:week_start] == anchor.to_date }
    before_size = before ? before[:cohort_size] : 0

    internal_user = make_user("m4_int@example.com", created_at: anchor + 1.day, internal: true)
    make_episode(internal_user, created_at: anchor + 1.week)

    after = BuildsAdminMetricsReport.call.cohort_retention.find { |r| r[:week_start] == anchor.to_date }
    after_size = after ? after[:cohort_size] : 0

    assert_equal before_size, after_size,
                 "adding an internal user must not grow the cohort_size"
  end

  # ----------------------- WAU -----------------------

  test "WAU counts distinct non-internal users with at least one episode that week" do
    anchor = 3.weeks.ago.beginning_of_week

    u1 = make_user("m5_u1@example.com", created_at: anchor - 1.day)
    u2 = make_user("m5_u2@example.com", created_at: anchor - 1.day)
    internal_user = make_user("m5_int@example.com", created_at: anchor - 1.day, internal: true)

    before = BuildsAdminMetricsReport.call.wau.find { |r| r[:week_start] == anchor.to_date } || { wau: 0 }

    make_episode(u1, created_at: anchor + 1.day)
    make_episode(u1, created_at: anchor + 2.days) # same user, still +1 WAU
    make_episode(u2, created_at: anchor + 3.days)
    make_episode(internal_user, created_at: anchor + 1.day) # excluded

    after = BuildsAdminMetricsReport.call.wau.find { |r| r[:week_start] == anchor.to_date }
    assert_not_nil after
    assert_equal 2, after[:wau] - before[:wau]
  end

  test "WAU % of cumulative is WAU divided by cumulative non-internal users at week end" do
    anchor = 2.weeks.ago.beginning_of_week

    u1 = make_user("m6_u1@example.com", created_at: anchor - 2.weeks)
    make_user("m6_u2@example.com", created_at: anchor - 2.weeks)
    make_user("m6_u3@example.com", created_at: anchor - 2.weeks)
    make_user("m6_u4@example.com", created_at: anchor - 2.weeks)

    make_episode(u1, created_at: anchor + 1.day)

    row = BuildsAdminMetricsReport.call.wau.find { |r| r[:week_start] == anchor.to_date }
    assert_not_nil row
    # WAU and cumulative are absolute values; just assert they are consistent.
    assert_operator row[:wau], :>=, 1
    assert_operator row[:cumulative_users], :>=, 4
    expected_pct = (row[:wau].to_f / row[:cumulative_users] * 100).round(2)
    assert_in_delta expected_pct, row[:wau_percent], 0.01
  end

  # ----------------------- Failure rate -----------------------

  test "failure rate reports total + failed counts + percent by week" do
    anchor = 2.weeks.ago.beginning_of_week
    user = make_user("m7_u@example.com", created_at: anchor - 1.week)

    before = BuildsAdminMetricsReport.call.failure_rate.find { |r| r[:week_start] == anchor.to_date } ||
             { total: 0, failed: 0 }

    make_episode(user, created_at: anchor + 1.day, status: "complete")
    make_episode(user, created_at: anchor + 2.days, status: "failed")
    make_episode(user, created_at: anchor + 3.days, status: "failed")
    make_episode(user, created_at: anchor + 4.days, status: "complete")

    after = BuildsAdminMetricsReport.call.failure_rate.find { |r| r[:week_start] == anchor.to_date }
    assert_not_nil after
    assert_equal 4, after[:total] - before[:total]
    assert_equal 2, after[:failed] - before[:failed]
  end

  test "failure rate excludes internal users' episodes" do
    anchor = 11.weeks.ago.beginning_of_week

    before = BuildsAdminMetricsReport.call.failure_rate.find { |r| r[:week_start] == anchor.to_date }
    before_total = before ? before[:total] : 0
    before_failed = before ? before[:failed] : 0

    internal_user = make_user("m8_int@example.com", created_at: anchor - 1.week, internal: true)
    make_episode(internal_user, created_at: anchor + 1.day, status: "failed")

    after = BuildsAdminMetricsReport.call.failure_rate.find { |r| r[:week_start] == anchor.to_date }
    after_total = after ? after[:total] : 0
    after_failed = after ? after[:failed] : 0

    assert_equal before_total, after_total,
                 "internal episode must not be counted in total"
    assert_equal before_failed, after_failed,
                 "internal failed episode must not be counted in failed"
  end
end
