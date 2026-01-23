# frozen_string_literal: true

require "test_helper"

class FormatsEpisodeDescriptionTest < ActiveSupport::TestCase
  test "returns description unchanged when source_url is nil" do
    description = "A great article about testing."

    result = FormatsEpisodeDescription.call(description: description, source_url: nil)

    assert_equal description, result
  end

  test "returns description unchanged when source_url is blank" do
    description = "A great article about testing."

    result = FormatsEpisodeDescription.call(description: description, source_url: "")

    assert_equal description, result
  end

  test "appends source_url to description with proper formatting" do
    description = "A great article about testing."
    source_url = "https://example.com/article"

    result = FormatsEpisodeDescription.call(description: description, source_url: source_url)

    expected = "A great article about testing.\n\nOriginal URL: https://example.com/article"
    assert_equal expected, result
  end

  test "handles empty description with source_url" do
    result = FormatsEpisodeDescription.call(description: "", source_url: "https://example.com/article")

    assert_equal "\n\nOriginal URL: https://example.com/article", result
  end

  test "preserves multiline description" do
    description = "Line one.\nLine two."
    source_url = "https://example.com/article"

    result = FormatsEpisodeDescription.call(description: description, source_url: source_url)

    expected = "Line one.\nLine two.\n\nOriginal URL: https://example.com/article"
    assert_equal expected, result
  end

  test "works with complex URLs" do
    description = "Article summary."
    source_url = "https://example.com/path?query=param&other=value#anchor"

    result = FormatsEpisodeDescription.call(description: description, source_url: source_url)

    assert_includes result, source_url
    assert result.end_with?(source_url)
  end
end
