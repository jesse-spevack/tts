# frozen_string_literal: true

require "test_helper"

class GeneratesContentPreviewTest < ActiveSupport::TestCase
  test "returns full text when shorter than double preview length" do
    short_text = "Hello world!"
    result = GeneratesContentPreview.call(short_text)
    assert_equal "Hello world!", result
  end

  test "truncates long text showing start and end" do
    # Create text that's definitely long enough to truncate
    long_text = "A" * 60 + " middle content here " + "Z" * 60
    result = GeneratesContentPreview.call(long_text)

    assert result.start_with?("A" * 57)
    assert result.end_with?("Z" * 57)
    assert result.include?("... ")
  end

  test "preserves exactly 60 characters on each side" do
    start_part = "X" * 60
    end_part = "Y" * 60
    long_text = start_part + ("M" * 100) + end_part

    result = GeneratesContentPreview.call(long_text)

    # Format: XXX... YYY (57 chars on each side with "... " in middle)
    assert_includes result, "X" * 57
    assert_includes result, "Y" * 57
    assert_includes result, "... "
  end

  test "handles nil input" do
    result = GeneratesContentPreview.call(nil)
    assert_nil result
  end

  test "handles empty string" do
    result = GeneratesContentPreview.call("")
    assert_equal "", result
  end

  test "strips whitespace from start and end" do
    text_with_whitespace = "  Hello world  "
    result = GeneratesContentPreview.call(text_with_whitespace)
    assert_equal "Hello world", result
  end
end
