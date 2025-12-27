# frozen_string_literal: true

require "test_helper"

class StripsMarkdownTest < ActiveSupport::TestCase
  test "removes h1 headers" do
    assert_equal "Title", StripsMarkdown.call("# Title")
  end

  test "removes h2-h6 headers" do
    assert_equal "Subtitle", StripsMarkdown.call("## Subtitle")
    assert_equal "Deep", StripsMarkdown.call("###### Deep")
  end

  test "removes bold formatting with asterisks" do
    assert_equal "bold text", StripsMarkdown.call("**bold text**")
  end

  test "removes bold formatting with underscores" do
    assert_equal "bold text", StripsMarkdown.call("__bold text__")
  end

  test "removes italic formatting with asterisks" do
    assert_equal "italic text", StripsMarkdown.call("*italic text*")
  end

  test "removes italic formatting with underscores" do
    assert_equal "italic text", StripsMarkdown.call("_italic text_")
  end

  test "removes strikethrough" do
    assert_equal "deleted", StripsMarkdown.call("~~deleted~~")
  end

  test "converts links to just the text" do
    assert_equal "click here", StripsMarkdown.call("[click here](https://example.com)")
  end

  test "removes images completely" do
    assert_equal "", StripsMarkdown.call("![alt text](image.png)").strip
  end

  test "removes images but keeps surrounding text" do
    assert_equal "Before  After", StripsMarkdown.call("Before ![img](url) After")
  end

  test "removes fenced code blocks" do
    input = "Before\n```ruby\ncode here\n```\nAfter"
    assert_equal "Before\n\nAfter", StripsMarkdown.call(input)
  end

  test "removes inline code but keeps content" do
    assert_equal "use the function method", StripsMarkdown.call("use the `function` method")
  end

  test "removes unordered list markers" do
    assert_equal "item one\nitem two", StripsMarkdown.call("- item one\n- item two")
  end

  test "removes ordered list markers" do
    assert_equal "first\nsecond", StripsMarkdown.call("1. first\n2. second")
  end

  test "removes blockquote markers" do
    assert_equal "quoted text", StripsMarkdown.call("> quoted text")
  end

  test "removes horizontal rules" do
    assert_equal "Above\n\nBelow", StripsMarkdown.call("Above\n---\nBelow")
  end

  test "removes HTML tags" do
    assert_equal "plain text", StripsMarkdown.call("<div>plain text</div>")
  end

  test "removes YAML frontmatter" do
    input = "---\ntitle: Test\nauthor: Me\n---\nContent here"
    assert_equal "Content here", StripsMarkdown.call(input)
  end

  test "collapses multiple newlines into double newlines" do
    input = "Para one\n\n\n\n\nPara two"
    assert_equal "Para one\n\nPara two", StripsMarkdown.call(input)
  end

  test "handles nil input" do
    assert_nil StripsMarkdown.call(nil)
  end

  test "handles empty string" do
    assert_equal "", StripsMarkdown.call("")
  end
end
