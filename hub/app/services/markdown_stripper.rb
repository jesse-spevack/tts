# frozen_string_literal: true

module MarkdownStripper
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_headers(text)
    text.strip
  end

  def self.remove_headers(text)
    text.gsub(/^\#{1,6}\s+/, "")
  end
end
