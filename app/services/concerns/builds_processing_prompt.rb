# frozen_string_literal: true

module BuildsProcessingPrompt
  extend ActiveSupport::Concern

  class_methods do
    def call(text:)
      new(text: text).call
    end
  end

  included do
    attr_reader :text
  end

  def initialize(text:)
    @text = text
  end

  private

  def json_output_format
    <<~FORMAT
      OUTPUT FORMAT (JSON only, no markdown):
      {
        "title": "...",
        "author": "...",
        "description": "...",
        "content": "..."
      }
    FORMAT
  end

  def shared_cleaning_rules
    <<~RULES
      - Expand abbreviations (e.g., "govt" -> "government")
      - Make lists sound natural when read aloud
    RULES
  end

  def author_instruction
    'The author\'s name — check the byline and article text if not in metadata (use "Unknown" if not found)'
  end
end
