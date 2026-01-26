# frozen_string_literal: true

require "test_helper"

class EmailEpisodeHelperTest < ActionView::TestCase
  include EmailEpisodeHelper

  test "maps LLM processing failed to friendly message" do
    assert_equal(
      "We had trouble processing your content. Please try again.",
      user_friendly_error("LLM processing failed")
    )
  end

  test "maps character limit exceeded to friendly message" do
    assert_equal(
      "This content exceeds your plan's character limit. Please shorten it or upgrade your plan.",
      user_friendly_error("Content exceeds your plan's character limit")
    )
  end

  test "maps content too short to friendly message" do
    assert_equal(
      "Your email content is too short. Please include more text.",
      user_friendly_error("Content must be at least 100 characters")
    )
  end

  test "maps empty content to friendly message" do
    assert_equal(
      "Your email appears to be empty. Please include some content.",
      user_friendly_error("Content cannot be empty")
    )
  end

  test "returns default message for unknown errors" do
    assert_equal(
      "Something went wrong processing your email. Please try again or visit the website to create an episode.",
      user_friendly_error("Some unexpected error occurred")
    )
  end

  test "returns default message for nil error" do
    assert_equal(
      "Something went wrong processing your email. Please try again or visit the website to create an episode.",
      user_friendly_error(nil)
    )
  end

  test "is case insensitive" do
    assert_equal(
      "We had trouble processing your content. Please try again.",
      user_friendly_error("llm PROCESSING FAILED")
    )
  end
end
