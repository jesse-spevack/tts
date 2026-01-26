# frozen_string_literal: true

module EmailEpisodeHelper
  ERROR_MESSAGES = {
    /LLM processing failed/i => "We had trouble processing your content. Please try again.",
    /content.*too (short|long)/i => "Your email content length doesn't meet our requirements.",
    /exceeds.*plan/i => "This content exceeds your plan's character limit. Please shorten it or upgrade your plan.",
    /character limit/i => "This content exceeds your plan's character limit.",
    /must be at least \d+ characters/i => "Your email content is too short. Please include more text.",
    /cannot be empty/i => "Your email appears to be empty. Please include some content."
  }.freeze

  def user_friendly_error(error)
    return default_error_message if error.nil?

    ERROR_MESSAGES.each do |pattern, friendly_message|
      return friendly_message if error.match?(pattern)
    end

    default_error_message
  end

  private

  def default_error_message
    "Something went wrong processing your email. Please try again or visit the website to create an episode."
  end
end
