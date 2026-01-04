# frozen_string_literal: true

class FormatsDuration
  def self.call(duration_seconds)
    new(duration_seconds).call
  end

  def initialize(duration_seconds)
    @duration_seconds = duration_seconds
  end

  def call
    return nil unless @duration_seconds

    minutes = @duration_seconds / 60
    seconds = @duration_seconds % 60
    format("%d:%02d", minutes, seconds)
  end
end
