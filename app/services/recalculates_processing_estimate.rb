# frozen_string_literal: true

# Rebuilds the ETA prediction model from historical processing data.
# Called after every episode completes.
#
# Model: processing_seconds = base_seconds + (source_text_length * microseconds_per_character / 1_000_000)
#
# The intercept captures fixed overhead (~10-15s for fetch/LLM/upload),
# the slope captures per-character TTS cost. Outliers beyond 3 standard
# deviations are filtered (e.g. stuck/retried episodes). Each recalculation
# appends a new ProcessingEstimate row for historical tracking.
class RecalculatesProcessingEstimate
  MINIMUM_EPISODES = 2
  OUTLIER_THRESHOLD = 3

  def self.call
    new.call
  end

  def call
    episodes = eligible_episodes
    return nil if episodes.length < MINIMUM_EPISODES

    data_points = episodes.filter_map do |episode|
      x = episode.source_text_length.to_f
      y = (episode.processing_completed_at - episode.processing_started_at).to_f
      [ x, y ] if y > 0
    end

    filtered = filter_outliers(data_points)
    return nil if filtered.length < MINIMUM_EPISODES

    slope, intercept = linear_fit(filtered)

    microseconds_per_character = [ (slope * 1_000_000).round, 1 ].max
    base_seconds = [ intercept.round, 0 ].max

    ProcessingEstimate.create!(
      base_seconds: base_seconds,
      microseconds_per_character: microseconds_per_character,
      episode_count: filtered.length
    )
  end

  private

  def eligible_episodes
    Episode
      .where.not(processing_started_at: nil)
      .where.not(processing_completed_at: nil)
      .where.not(source_text_length: nil)
      .select(:id, :source_text_length, :processing_started_at, :processing_completed_at)
  end

  def filter_outliers(data_points)
    processing_times = data_points.map(&:last)
    mean = processing_times.sum / processing_times.length.to_f
    variance = processing_times.sum { |t| (t - mean)**2 } / processing_times.length.to_f
    std_dev = Math.sqrt(variance)

    return data_points if std_dev.zero?

    data_points.select do |_, y|
      (y - mean).abs <= OUTLIER_THRESHOLD * std_dev
    end
  end

  def linear_fit(data_points)
    xs = data_points.map(&:first)
    ys = data_points.map(&:last)

    mean_x = xs.sum / xs.length.to_f
    mean_y = ys.sum / ys.length.to_f

    numerator = data_points.sum { |x, y| (x - mean_x) * (y - mean_y) }
    denominator = data_points.sum { |x, _| (x - mean_x)**2 }

    if denominator.zero?
      slope = 0.0
    else
      slope = numerator / denominator
    end

    intercept = mean_y - slope * mean_x

    [ slope, intercept ]
  end
end
