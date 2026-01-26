# frozen_string_literal: true

class BuildsEmailProcessingPrompt
  include BuildsProcessingPrompt

  def call
    <<~PROMPT
      You are processing email content for text-to-speech conversion.

      INPUT:
      #{text}

      TASKS:
      1. Extract metadata:
         - title: Infer an appropriate title from the content
         - author: #{author_instruction}
         - description: A single sentence summary

      2. Clean and optimize the content for listening:
         - Remove email signatures (e.g., "Best regards", "Sent from my iPhone", "Thanks,")
         - Remove quoted reply text (lines starting with > or "On [date] [person] wrote:")
         - Remove disclaimer/confidentiality notices
         - Remove salutations and sign-offs (e.g., "Hi John,", "Dear Team,")
         - Remove unsubscribe links and email footers
         - Remove navigation menus, headers, footers if present
         - Fix formatting issues from email (extra whitespace, broken paragraphs)
         #{shared_cleaning_rules}
         - Remove any URLs or email addresses
         - Keep the main content faithful to the original

      #{json_output_format}
    PROMPT
  end
end
