# frozen_string_literal: true

class BuildsPasteProcessingPrompt
  include BuildsProcessingPrompt

  def call
    <<~PROMPT
      You are processing pasted text for text-to-speech conversion.

      INPUT:
      #{text}

      TASKS:
      1. Extract metadata:
         - title: Infer an appropriate title from the content
         - author: #{author_instruction}
         - description: A single sentence summary

      2. Clean and optimize the content for listening:
         - Remove navigation menus, headers, footers, and sidebars
         - Remove cookie banners, "Subscribe to newsletter" CTAs, and ads
         - Remove social media links and share buttons
         - Fix formatting issues from copy/paste (extra whitespace, broken paragraphs)
         #{shared_cleaning_rules}
         - Remove any URLs or email addresses
         - Keep the main article content faithful to the original

      #{json_output_format}
    PROMPT
  end
end
