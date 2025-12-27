# frozen_string_literal: true

class BuildsPasteProcessingPrompt
  def self.call(text:)
    new(text: text).call
  end

  def initialize(text:)
    @text = text
  end

  def call
    <<~PROMPT
      You are processing pasted text for text-to-speech conversion.

      INPUT:
      #{text}

      TASKS:
      1. Extract metadata:
         - title: Infer an appropriate title from the content
         - author: The author's name if mentioned (use "Unknown" if not found)
         - description: A single sentence summary

      2. Clean and optimize the content for listening:
         - Remove navigation menus, headers, footers, and sidebars
         - Remove cookie banners, "Subscribe to newsletter" CTAs, and ads
         - Remove social media links and share buttons
         - Fix formatting issues from copy/paste (extra whitespace, broken paragraphs)
         - Expand abbreviations (e.g., "govt" -> "government")
         - Make lists sound natural when read aloud
         - Remove any URLs or email addresses
         - Keep the main article content faithful to the original

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
