# frozen_string_literal: true

module EpisodePlaceholders
  TITLE = "Processing..."
  AUTHOR = "Processing..."

  DESCRIPTIONS = {
    url: "Processing article from URL...",
    paste: "Processing pasted text...",
    file: "Processing uploaded file...",
    email: "Processing email content..."
  }.freeze

  def self.description_for(source_type)
    DESCRIPTIONS[source_type.to_sym] || "Processing..."
  end
end
