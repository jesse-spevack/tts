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

  test "removes unordered list markers" do
    assert_equal "item one\nitem two", MarkdownStripper.strip("- item one\n- item two")
  end

  test "removes ordered list markers" do
    assert_equal "first\nsecond", MarkdownStripper.strip("1. first\n2. second")
  end

  test "removes blockquote markers" do
    assert_equal "quoted text", MarkdownStripper.strip("> quoted text")
  end

  test "removes horizontal rules" do
    assert_equal "Above\n\nBelow", MarkdownStripper.strip("Above\n---\nBelow")
  end

  test "removes HTML tags" do
    assert_equal "plain text", MarkdownStripper.strip("<div>plain text</div>")
  end

  test "removes YAML frontmatter" do
    input = "---\ntitle: Test\nauthor: Me\n---\nContent here"
    assert_equal "Content here", MarkdownStripper.strip(input)
  end

  test "collapses multiple newlines into double newlines" do
    input = "Para one\n\n\n\n\nPara two"
    assert_equal "Para one\n\nPara two", MarkdownStripper.strip(input)
  end

  test "handles nil input" do
    assert_nil MarkdownStripper.strip(nil)
  end

  test "handles empty string" do
    assert_equal "", MarkdownStripper.strip("")
  end
end
