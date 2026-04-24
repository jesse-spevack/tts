# frozen_string_literal: true

# Computes the metrics shown on /admin/metrics.
#
# All queries exclude users flagged as internal (User#internal) so the numbers
# reflect real users only. Internal accounts (Jesse + test user) would otherwise
# distort small-N metrics.
#
# At ~50 users, we intentionally favor readable Ruby aggregation over clever SQL.
# All "by week" aggregations bucket in Ruby using Date#beginning_of_week.
#
# Weeks start on Monday (Rails default). A week is identified by its Monday date.
class BuildsAdminMetricsReport
  COHORT_WEEKS = 12
  WAU_WEEKS = 12
  FAILURE_RATE_WEEKS = 12

  # Relative weeks to show in the cohort retention grid (N+1, N+2, N+4).
  COHORT_RELATIVE_WEEKS = [ 1, 2, 4 ].freeze

  Report = Data.define(:activation, :cohort_retention, :wau, :failure_rate)

  def self.call
    new.call
  end

  def call
    Report.new(
      activation: activation,
      cohort_retention: cohort_retention,
      wau: wau,
      failure_rate: failure_rate
    )
  end

  private

  # --- Activation -------------------------------------------------------------

  # "New signups in the last N days" counts non-internal users created in that window.
  # "Activation" for the last 30-day cohort = the fraction of those signups who
  # created ≥ 1 episode within 7 days of their signup.
  def activation
    signups_7d = User.where(internal: false).where(created_at: 7.days.ago..).count
    cohort_30d = User.where(internal: false).where(created_at: 30.days.ago..)
    cohort_size = cohort_30d.count
    activated = cohort_30d.select { |u| activated_within_7_days?(u) }.size
    rate = cohort_size.zero? ? 0.0 : (activated.to_f / cohort_size * 100).round(2)

    {
      signups_7d: signups_7d,
      signups_30d: cohort_size,
      cohort_size_30d: cohort_size,
      activated_30d: activated,
      activation_rate_30d: rate
    }
  end

  def activated_within_7_days?(user)
    window_end = user.created_at + 7.days
    Episode.unscoped
      .where(user_id: user.id)
      .where(created_at: user.created_at..window_end)
      .exists?
  end

  # --- Cohort retention -------------------------------------------------------

  # For each of the last COHORT_WEEKS signup cohorts (weeks), report:
  #   - cohort_size (non-internal signups that week)
  #   - active_week_{1,2,4}: # of users in that cohort who created ≥1 episode
  #     during the N'th following week (relative to their cohort week).
  #
  # Empty cohorts (no non-internal signups) are omitted.
  def cohort_retention
    cutoff = COHORT_WEEKS.weeks.ago.beginning_of_week
    users = User.where(internal: false).where(created_at: cutoff..).to_a
    return [] if users.empty?

    cohorts = users.group_by { |u| u.created_at.to_date.beginning_of_week }
    user_ids = users.map(&:id)

    # Preload episodes (user_id, created_at) for all cohort members in one query.
    episodes_by_user = Episode.unscoped
      .where(user_id: user_ids)
      .pluck(:user_id, :created_at)
      .group_by(&:first)

    cohorts.sort_by { |week_start, _| week_start }.map do |week_start, cohort_users|
      row = {
        week_start: week_start,
        cohort_size: cohort_users.size
      }

      COHORT_RELATIVE_WEEKS.each do |rel_week|
        rel_start = week_start + rel_week.weeks
        rel_end = rel_start + 1.week
        active = cohort_users.count do |u|
          (episodes_by_user[u.id] || []).any? do |(_uid, created_at)|
            created_at >= rel_start && created_at < rel_end
          end
        end
        row[:"active_week_#{rel_week}"] = active
      end

      row
    end
  end

  # --- WAU --------------------------------------------------------------------

  # Weekly Active Users for the last WAU_WEEKS weeks:
  #   - wau: distinct non-internal users with ≥ 1 episode that week
  #   - cumulative_users: total non-internal users signed up on or before the
  #     last day of that week
  #   - wau_percent: wau / cumulative_users * 100
  def wau
    this_monday = Date.current.beginning_of_week
    weeks = (0...WAU_WEEKS).map { |i| this_monday - i.weeks }.sort

    earliest = weeks.first
    non_internal_ids = User.where(internal: false).pluck(:id).to_set

    # user_id, episode created_at for non-internal episodes in range.
    episode_rows = Episode.unscoped
      .where(user_id: non_internal_ids.to_a)
      .where(created_at: earliest..)
      .pluck(:user_id, :created_at)

    # All non-internal users with their created_at (for cumulative counts).
    user_created_ats = User.where(internal: false).pluck(:created_at).sort

    weeks.map do |week_start|
      week_end = week_start + 1.week
      active_user_ids = episode_rows.each_with_object(Set.new) do |(uid, created_at), set|
        set << uid if created_at >= week_start && created_at < week_end
      end
      cumulative = user_created_ats.count { |t| t < week_end }
      percent = cumulative.zero? ? 0.0 : (active_user_ids.size.to_f / cumulative * 100).round(2)

      {
        week_start: week_start,
        wau: active_user_ids.size,
        cumulative_users: cumulative,
        wau_percent: percent
      }
    end
  end

  # --- Failure rate -----------------------------------------------------------

  # For each of the last FAILURE_RATE_WEEKS weeks, report:
  #   - total: # of non-internal episodes created that week
  #   - failed: # with status = 'failed'
  #   - failure_percent: failed/total * 100
  #
  # Weeks with zero non-internal episodes are omitted.
  def failure_rate
    this_monday = Date.current.beginning_of_week
    earliest = this_monday - (FAILURE_RATE_WEEKS - 1).weeks
    latest_end = this_monday + 1.week

    non_internal_ids = User.where(internal: false).pluck(:id)

    rows = Episode.unscoped
      .where(user_id: non_internal_ids)
      .where(created_at: earliest...latest_end)
      .pluck(:status, :created_at)

    grouped = rows.group_by { |(_status, created_at)| created_at.to_date.beginning_of_week }

    grouped.sort_by { |week_start, _| week_start }.map do |week_start, entries|
      total = entries.size
      failed = entries.count { |(status, _)| status == "failed" }
      percent = total.zero? ? 0.0 : (failed.to_f / total * 100).round(2)

      {
        week_start: week_start,
        total: total,
        failed: failed,
        failure_percent: percent
      }
    end
  end
end
