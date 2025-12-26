# frozen_string_literal: true

require "test_helper"

class PasteProcessingPromptTest < ActiveSupport::TestCase
  test "builds prompt with text content" do
    text = "This is my pasted article content."
    prompt = PasteProcessingPrompt.build(text: text)

    assert_includes prompt, text
  end

  test "includes metadata extraction instructions" do
    prompt = PasteProcessingPrompt.build(text: "test")

    assert_includes prompt, "title"
    assert_includes prompt, "author"
    assert_includes prompt, "description"
  end

  test "includes TTS optimization instructions" do
    prompt = PasteProcessingPrompt.build(text: "test")

    assert_includes prompt, "text-to-speech"
  end

  test "requests JSON output format" do
    prompt = PasteProcessingPrompt.build(text: "test")

    assert_includes prompt, "JSON"
    assert_includes prompt, "content"
  end

  test "does not mention web article" do
    prompt = PasteProcessingPrompt.build(text: "test")

    refute_includes prompt, "web article"
  end

  test "includes instructions to remove webpage boilerplate" do
    prompt = PasteProcessingPrompt.build(text: "test")

    assert_includes prompt, "navigation"
    assert_includes prompt, "cookie"
    assert_includes prompt, "Subscribe"
  end
end
