require "test_helper"

class UrlProcessingPromptTest < ActiveSupport::TestCase
  test "builds prompt with text content" do
    prompt = UrlProcessingPrompt.build(text: "This is article content.")

    assert_includes prompt, "This is article content."
    assert_includes prompt, "text-to-speech"
    assert_includes prompt, "JSON"
  end

  test "includes all required output fields in instructions" do
    prompt = UrlProcessingPrompt.build(text: "Content")

    assert_includes prompt, "title"
    assert_includes prompt, "author"
    assert_includes prompt, "description"
    assert_includes prompt, "content"
  end
end
