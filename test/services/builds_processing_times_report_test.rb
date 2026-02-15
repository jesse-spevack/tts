# frozen_string_literal: true

require "test_helper"

class BuildsProcessingTimesReportTest < ActiveSupport::TestCase
  test "returns a report with chart_points, total_episode_count, current_estimate, and estimate_history" do
    episode = episodes(:complete)
    episode.update_columns(
      processing_started_at: 2.minutes.ago,
      processing_completed_at: 1.minute.ago,
      source_text_length: 5000
    )

    report = BuildsProcessingTimesReport.call

    assert_equal 1, report.chart_points.size
    assert_equal 1, report.total_episode_count
    assert_equal 5000, report.chart_points.first[:length]
    assert_in_delta 60.0, report.chart_points.first[:seconds], 1.0
  end

  test "returns current estimate and history" do
    report = BuildsProcessingTimesReport.call

    assert_not_nil report.current_estimate
    assert_kind_of ActiveRecord::Relation, report.estimate_history
  end

  test "returns empty chart_points when no episodes have processing data" do
    report = BuildsProcessingTimesReport.call

    assert_empty report.chart_points
    assert_equal 0, report.total_episode_count
  end

  test "returns nil current_estimate when no estimates exist" do
    ProcessingEstimate.delete_all

    report = BuildsProcessingTimesReport.call

    assert_nil report.current_estimate
    assert_empty report.estimate_history
  end

  test "limits chart points to 500" do
    assert_equal 500, BuildsProcessingTimesReport::CHART_LIMIT
  end

  test "limits estimate history to 10" do
    assert_equal 10, BuildsProcessingTimesReport::HISTORY_LIMIT
  end

  test "includes soft-deleted episodes in chart" do
    episode = episodes(:complete)
    episode.update_columns(
      processing_started_at: 2.minutes.ago,
      processing_completed_at: 1.minute.ago,
      source_text_length: 5000,
      deleted_at: 1.hour.ago
    )

    report = BuildsProcessingTimesReport.call

    assert_equal 1, report.chart_points.size
  end
end
