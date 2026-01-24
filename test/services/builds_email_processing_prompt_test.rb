# frozen_string_literal: true

require "test_helper"

class BuildsEmailProcessingPromptTest < ActiveSupport::TestCase
  test "builds prompt with text content" do
    text = "This is my email content."
    prompt = BuildsEmailProcessingPrompt.call(text: text)

    assert_includes prompt, text
  end

  test "includes metadata extraction instructions" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "title"
    assert_includes prompt, "author"
    assert_includes prompt, "description"
  end

  test "includes TTS optimization instructions" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "text-to-speech"
  end

  test "requests JSON output format" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "JSON"
    assert_includes prompt, "content"
  end

  test "includes email-specific cleaning instructions" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "email signatures"
    assert_includes prompt, "Best regards"
    assert_includes prompt, "Sent from my iPhone"
  end

  test "includes instructions to remove quoted replies" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "quoted reply"
  end

  test "includes instructions to remove disclaimers" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "disclaimer"
  end

  test "includes instructions to remove salutations" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "salutations"
    assert_includes prompt, "sign-offs"
  end

  test "includes instructions to remove unsubscribe links" do
    prompt = BuildsEmailProcessingPrompt.call(text: "test")

    assert_includes prompt, "unsubscribe"
  end
end
