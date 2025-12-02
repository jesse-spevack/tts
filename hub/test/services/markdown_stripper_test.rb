# frozen_string_literal: true

require "test_helper"

class MarkdownStripperTest < ActiveSupport::TestCase
  test "removes h1 headers" do
    assert_equal "Title", MarkdownStripper.strip("# Title")
  end

  test "removes h2-h6 headers" do
    assert_equal "Subtitle", MarkdownStripper.strip("## Subtitle")
    assert_equal "Deep", MarkdownStripper.strip("###### Deep")
  end

  test "removes bold formatting with asterisks" do
    assert_equal "bold text", MarkdownStripper.strip("**bold text**")
  end

  test "removes bold formatting with underscores" do
    assert_equal "bold text", MarkdownStripper.strip("__bold text__")
  end

  test "removes italic formatting with asterisks" do
    assert_equal "italic text", MarkdownStripper.strip("*italic text*")
  end

  test "removes italic formatting with underscores" do
    assert_equal "italic text", MarkdownStripper.strip("_italic text_")
  end

  test "removes strikethrough" do
    assert_equal "deleted", MarkdownStripper.strip("~~deleted~~")
  end

  test "converts links to just the text" do
    assert_equal "click here", MarkdownStripper.strip("[click here](https://example.com)")
  end

  test "removes images completely" do
    assert_equal "", MarkdownStripper.strip("![alt text](image.png)").strip
  end

  test "removes images but keeps surrounding text" do
    assert_equal "Before  After", MarkdownStripper.strip("Before ![img](url) After")
  end

  test "removes fenced code blocks" do
    input = "Before\n```ruby\ncode here\n```\nAfter"
    assert_equal "Before\n\nAfter", MarkdownStripper.strip(input)
  end

  test "removes inline code but keeps content" do
    assert_equal "use the function method", MarkdownStripper.strip("use the `function` method")
  end
end
