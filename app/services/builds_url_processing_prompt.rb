class BuildsUrlProcessingPrompt
  def self.call(text:)
    new(text: text).call
  end

  def initialize(text:)
    @text = text
  end

  def call
    <<~PROMPT
      You are processing a web article for text-to-speech conversion.

      INPUT:
      #{text}

      TASKS:
      1. Extract metadata:
         - title: The article's title
         - author: The author's name (use "Unknown" if not found)
         - description: A single sentence summary

      2. Clean and optimize the content:
         - Remove any leftover navigation, ads, or boilerplate
         - Remove "Subscribe to newsletter" type CTAs
         - Remove any image references or descriptions
         - Expand abbreviations (e.g., "govt" -> "government")
         - Make lists sound natural when read aloud

      OUTPUT FORMAT (JSON only, no markdown):
      {
        "title": "...",
        "author": "...",
        "description": "...",
        "content": "..."
      }
    PROMPT
  end

  private

  attr_reader :text
end
