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
end
