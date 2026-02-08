# frozen_string_literal: true

require "test_helper"

class BuildsProcessingPromptTest < ActiveSupport::TestCase
  class TestPromptBuilder
    include BuildsProcessingPrompt

    def call
      "#{text} | #{author_instruction} | #{json_output_format} | #{shared_cleaning_rules}"
    end
  end

  test ".call delegates to instance" do
    result = TestPromptBuilder.call(text: "hello")
    assert_includes result, "hello"
  end

  test "author_instruction includes Unknown fallback" do
    result = TestPromptBuilder.call(text: "test")
    assert_includes result, 'use "Unknown" if not found'
  end

  test "json_output_format includes all required fields" do
    result = TestPromptBuilder.call(text: "test")
    %w[title author description content].each do |field|
      assert_includes result, "\"#{field}\":"
    end
  end

  test "shared_cleaning_rules includes abbreviation expansion" do
    result = TestPromptBuilder.call(text: "test")
    assert_includes result, "Expand abbreviations"
  end

  test "author_instruction encourages finding author from bylines and article text" do
    result = TestPromptBuilder.call(text: "test")
    assert_includes result, "byline"
    assert_includes result, "article text"
  end
end
