# frozen_string_literal: true

class EstimatesProcessingTime
  DEFAULT_BASE_SECONDS = 10
  DEFAULT_MICROSECONDS_PER_CHARACTER = 3000

  def self.call(source_text_length:)
    new(source_text_length: source_text_length).call
  end

  def initialize(source_text_length:)
    @source_text_length = source_text_length
  end

  def call
    estimate = ProcessingEstimate.order(created_at: :desc).first

    base = estimate&.base_seconds || DEFAULT_BASE_SECONDS
    rate = estimate&.microseconds_per_character || DEFAULT_MICROSECONDS_PER_CHARACTER

    (base + (@source_text_length * rate / 1_000_000.0)).round
  end
end
