# frozen_string_literal: true

class ContentPreview
  PREVIEW_LENGTH = 60
  ELLIPSIS = "..."

  def self.generate(text)
    return nil if text.nil?

    text = text.strip
    return text if text.empty?

    # If text is short enough, return as-is
    # Need room for: start(57) + ellipsis(3) + space + quote + space + quote + ellipsis(3) + end(57)
    min_truncation_length = (PREVIEW_LENGTH * 2) + 10
    return text if text.length <= min_truncation_length

    start_chars = PREVIEW_LENGTH - ELLIPSIS.length
    end_chars = PREVIEW_LENGTH - ELLIPSIS.length

    start_part = text[0, start_chars].strip + ELLIPSIS
    end_part = ELLIPSIS + text[-end_chars, end_chars].strip

    "#{start_part}\" \"#{end_part}"
  end
end
