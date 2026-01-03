# frozen_string_literal: true

class BuildsUrlProcessingPrompt
  include BuildsProcessingPrompt

  def call
    <<~PROMPT
      You are processing a web article for text-to-speech conversion.

      INPUT:
      #{text}

      TASKS:
      1. Extract metadata:
         - title: The article's title
         - author: #{author_instruction}
         - description: A single sentence summary

      2. Clean and optimize the content:
         - Remove any leftover navigation, ads, or boilerplate
         - Remove "Subscribe to newsletter" type CTAs
         - Remove any image references or descriptions
         #{shared_cleaning_rules}

      #{json_output_format}
    PROMPT
  end
end
