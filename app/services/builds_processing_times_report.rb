# frozen_string_literal: true

class BuildsProcessingTimesReport
  CHART_LIMIT = 500
  HISTORY_LIMIT = 10

  def self.call
    new.call
  end

  def call
    episodes = chart_episodes

    Report.new(
      chart_points: build_chart_points(episodes),
      total_episode_count: total_episode_count,
      current_estimate: ProcessingEstimate.order(created_at: :desc).first,
      estimate_history: ProcessingEstimate.order(created_at: :desc).limit(HISTORY_LIMIT)
    )
  end

  private

  Report = Data.define(:chart_points, :total_episode_count, :current_estimate, :estimate_history)

  def chart_episodes
    episodes_scope
      .select(:id, :source_text_length, :processing_started_at, :processing_completed_at, :title)
      .order(processing_completed_at: :desc)
      .limit(CHART_LIMIT)
  end

  def total_episode_count
    episodes_scope.count
  end

  def episodes_scope
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
end
