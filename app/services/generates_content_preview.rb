# frozen_string_literal: true

class GeneratesContentPreview
  PREVIEW_LENGTH = 60
  ELLIPSIS = "..."

  def self.call(text)
    new(text).call
  end

  def initialize(text)
    @text = text
  end

  def call
    return nil if text.nil?

    stripped = text.strip
    return stripped if stripped.empty?

    min_truncation_length = (PREVIEW_LENGTH * 2) + 10
    return stripped if stripped.length <= min_truncation_length

    start_chars = PREVIEW_LENGTH - ELLIPSIS.length
    end_chars = PREVIEW_LENGTH - ELLIPSIS.length

    start_part = stripped[0, start_chars].strip
    end_part = stripped[-end_chars, end_chars].strip

    "#{start_part}... #{end_part}"
  end

  private

  attr_reader :text
end
