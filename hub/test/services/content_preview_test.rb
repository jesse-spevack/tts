# frozen_string_literal: true

require "test_helper"

class ContentPreviewTest < ActiveSupport::TestCase
  test "returns full text when shorter than double preview length" do
    short_text = "Hello world!"
    result = ContentPreview.generate(short_text)
    assert_equal "Hello world!", result
  end

  test "truncates long text showing start and end" do
    # Create text that's definitely long enough to truncate
    long_text = "A" * 60 + " middle content here " + "Z" * 60
    result = ContentPreview.generate(long_text)

    assert result.start_with?("A" * 57)
    assert result.end_with?("Z" * 57)
    assert result.include?("... ")
  end

  test "preserves exactly 60 characters on each side" do
    start_part = "X" * 60
    end_part = "Y" * 60
    long_text = start_part + ("M" * 100) + end_part

    result = ContentPreview.generate(long_text)

    # Format: XXX... YYY (57 chars on each side with "... " in middle)
    assert_includes result, "X" * 57
    assert_includes result, "Y" * 57
    assert_includes result, "... "
  end

  test "handles nil input" do
    result = ContentPreview.generate(nil)
    assert_nil result
  end

  test "handles empty string" do
    result = ContentPreview.generate("")
    assert_equal "", result
  end

  test "strips whitespace from start and end" do
    text_with_whitespace = "  Hello world  "
    result = ContentPreview.generate(text_with_whitespace)
    assert_equal "Hello world", result
  end

  test "strips markdown headers before generating preview" do
    markdown = "# Title\n\nThis is the content"
    result = ContentPreview.generate(markdown)
    refute_includes result, "#"
    assert_includes result, "Title"
  end

  test "strips markdown formatting before generating preview" do
    markdown = "**Bold** and *italic* text"
    result = ContentPreview.generate(markdown)
    refute_includes result, "*"
    assert_includes result, "Bold"
    assert_includes result, "italic"
  end

  test "strips markdown links before generating preview" do
    markdown = "Click [here](https://example.com) to continue"
    result = ContentPreview.generate(markdown)
    refute_includes result, "["
    refute_includes result, "]"
    refute_includes result, "("
    assert_includes result, "here"
  end

  test "strips complex markdown document" do
    markdown = <<~MD
      # Welcome

      This is **important** content with a [link](http://example.com).

      - Item one
      - Item two

      > A quote here
    MD
    result = ContentPreview.generate(markdown)
    refute_includes result, "#"
    refute_includes result, "**"
    refute_includes result, "["
    refute_includes result, "-"
    refute_includes result, ">"
  end
end
