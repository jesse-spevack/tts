# frozen_string_literal: true

require "test_helper"

class ProcessingEstimateTest < ActiveSupport::TestCase
  test "valid with all required attributes" do
    estimate = ProcessingEstimate.new(
      base_seconds: 10,
      microseconds_per_character: 3000,
      episode_count: 5
    )

    assert estimate.valid?
  end

  test "requires base_seconds" do
    estimate = ProcessingEstimate.new(
      microseconds_per_character: 3000,
      episode_count: 5
    )

    assert_not estimate.valid?
    assert_includes estimate.errors[:base_seconds], "can't be blank"
  end

  test "requires microseconds_per_character" do
    estimate = ProcessingEstimate.new(
      base_seconds: 10,
      episode_count: 5
    )

    assert_not estimate.valid?
    assert_includes estimate.errors[:microseconds_per_character], "can't be blank"
  end

  test "requires episode_count" do
    estimate = ProcessingEstimate.new(
      base_seconds: 10,
      microseconds_per_character: 3000
    )

    assert_not estimate.valid?
    assert_includes estimate.errors[:episode_count], "can't be blank"
  end

  test "base_seconds must be greater than or equal to 0" do
    estimate = ProcessingEstimate.new(
      base_seconds: -1,
      microseconds_per_character: 3000,
      episode_count: 5
    )

    assert_not estimate.valid?
    assert estimate.errors[:base_seconds].any? { |e| e.include?("greater than or equal to 0") }
  end

  test "base_seconds can be 0" do
    estimate = ProcessingEstimate.new(
      base_seconds: 0,
      microseconds_per_character: 3000,
      episode_count: 5
    )

    assert estimate.valid?
  end

  test "microseconds_per_character must be greater than 0" do
    estimate = ProcessingEstimate.new(
      base_seconds: 10,
      microseconds_per_character: 0,
      episode_count: 5
    )

    assert_not estimate.valid?
    assert estimate.errors[:microseconds_per_character].any? { |e| e.include?("greater than 0") }
  end

  test "episode_count must be greater than 0" do
    estimate = ProcessingEstimate.new(
      base_seconds: 10,
      microseconds_per_character: 3000,
      episode_count: 0
    )

    assert_not estimate.valid?
    assert estimate.errors[:episode_count].any? { |e| e.include?("greater than 0") }
  end

  test "fixture is valid" do
    estimate = processing_estimates(:recent)

    assert_equal 8, estimate.base_seconds
    assert_equal 2500, estimate.microseconds_per_character
    assert_equal 100, estimate.episode_count
  end
end
