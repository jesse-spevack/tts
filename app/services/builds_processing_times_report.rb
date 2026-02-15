# frozen_string_literal: true

class BuildsProcessingTimesReport
  CHART_LIMIT = 500
  HISTORY_LIMIT = 10

  def self.call
    new.call
  end

  def call
    points = build_chart_points(chart_episodes)
    outlier_threshold = compute_outlier_threshold(points)

    Report.new(
      chart_points: points.map { |p| p.merge(outlier: p[:seconds] > outlier_threshold) },
      max_length: points.map { |p| p[:length] }.max.to_f,
      max_seconds: points.map { |p| p[:seconds] }.max.to_f,
      total_episode_count: total_episode_count,
      current_estimate: ProcessingEstimate.order(created_at: :desc).first,
      estimate_history: ProcessingEstimate.order(created_at: :desc).limit(HISTORY_LIMIT)
    )
  end

  private

  OUTLIER_MULTIPLIER = 4

  Report = Data.define(:chart_points, :max_length, :max_seconds, :total_episode_count, :current_estimate, :estimate_history)

  def chart_episodes
    completed_episodes_with_timing
      .select(:id, :source_text_length, :processing_started_at, :processing_completed_at, :title)
      .order(processing_completed_at: :desc)
      .limit(CHART_LIMIT)
  end

  def total_episode_count
    completed_episodes_with_timing.count
  end

  def completed_episodes_with_timing
    Episode.unscoped
      .where(status: "complete")
      .where.not(processing_started_at: nil)
      .where.not(processing_completed_at: nil)
      .where.not(source_text_length: nil)
  end

  def build_chart_points(episodes)
    episodes.map do |ep|
      seconds = (ep.processing_completed_at - ep.processing_started_at).to_f
      { length: ep.source_text_length, seconds: seconds, title: ep.title }
    end
  end

  def compute_outlier_threshold(points)
    return Float::INFINITY if points.empty?

    sorted = points.map { |p| p[:seconds] }.sort
    sorted[sorted.length / 2] * OUTLIER_MULTIPLIER
  end
end
