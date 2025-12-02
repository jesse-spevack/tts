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
end
