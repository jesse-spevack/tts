# frozen_string_literal: true

require "test_helper"

class EstimatesProcessingTimeTest < ActiveSupport::TestCase
  test "returns estimated seconds using the latest ProcessingEstimate row" do
    # The :recent fixture has base_seconds=8, microseconds_per_character=2500
    # For 15000 chars: 8 + (15000 * 2500 / 1_000_000.0) = 8 + 37.5 = 45.5 -> 46
    result = EstimatesProcessingTime.call(source_text_length: 15000)
    assert_equal 46, result
  end

  test "uses the most recent estimate, not older ones" do
    # The :older fixture has base_seconds=12, microseconds_per_character=4000
    # but the :recent fixture (created 1 hour ago) should be used instead
    result = EstimatesProcessingTime.call(source_text_length: 10000)
    # 8 + (10000 * 2500 / 1_000_000.0) = 8 + 25.0 = 33
    assert_equal 33, result
  end

  test "uses hardcoded defaults when no ProcessingEstimate rows exist" do
    ProcessingEstimate.delete_all

    # Defaults: base_seconds=10, microseconds_per_character=3000
    # For 15000 chars: 10 + (15000 * 3000 / 1_000_000.0) = 10 + 45.0 = 55
    result = EstimatesProcessingTime.call(source_text_length: 15000)
    assert_equal 55, result
  end

  test "always reads fresh estimate from database" do
    # First call uses :recent fixture (base=8, rate=2500)
    result1 = EstimatesProcessingTime.call(source_text_length: 1000)
    assert_equal 11, result1

    # Create a newer estimate
    ProcessingEstimate.create!(base_seconds: 5, microseconds_per_character: 2000, episode_count: 50)

    # Second call should use the new estimate (base=5, rate=2000)
    # 5 + (1000 * 2000 / 1_000_000.0) = 5 + 2.0 = 7
    result2 = EstimatesProcessingTime.call(source_text_length: 1000)
    assert_equal 7, result2
  end

  test "handles zero source_text_length" do
    # base_seconds=8, rate=2500: 8 + (0 * 2500 / 1_000_000.0) = 8
    result = EstimatesProcessingTime.call(source_text_length: 0)
    assert_equal 8, result
  end

  test "handles large source_text_length" do
    # base_seconds=8, rate=2500: 8 + (1_000_000 * 2500 / 1_000_000.0) = 8 + 2500 = 2508
    result = EstimatesProcessingTime.call(source_text_length: 1_000_000)
    assert_equal 2508, result
  end
end
