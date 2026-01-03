# frozen_string_literal: true

require "test_helper"

module Tts
  class ConstantsTest < ActiveSupport::TestCase
    test "CONTENT_FILTER_ERROR is defined" do
      assert_equal "sensitive or harmful content", Tts::Constants::CONTENT_FILTER_ERROR
    end

    test "DEADLINE_EXCEEDED_ERROR is defined" do
      assert_equal "Deadline Exceeded", Tts::Constants::DEADLINE_EXCEEDED_ERROR
    end
  end
end
