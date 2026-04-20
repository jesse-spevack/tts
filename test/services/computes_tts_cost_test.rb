# frozen_string_literal: true

require "test_helper"

class ComputesTtsCostTest < ActiveSupport::TestCase
  test "standard tier: 1,000,000 chars = 400 cents ($4)" do
    assert_equal 400, ComputesTtsCost.call(voice_tier: "standard", character_count: 1_000_000)
  end

  test "premium tier: 1,000,000 chars = 3000 cents ($30)" do
    assert_equal 3_000, ComputesTtsCost.call(voice_tier: "premium", character_count: 1_000_000)
  end

  test "standard tier: 1000 chars = 1 cent (ceil from 0.4)" do
    # 1000 * 400 / 1_000_000 = 0.4 → ceil → 1
    assert_equal 1, ComputesTtsCost.call(voice_tier: "standard", character_count: 1_000)
  end

  test "premium tier: 1000 chars = 3 cents" do
    # 1000 * 3000 / 1_000_000 = 3.0 → 3
    assert_equal 3, ComputesTtsCost.call(voice_tier: "premium", character_count: 1_000)
  end

  test "standard tier: 2500 chars ceils to 1 cent" do
    # 2500 * 400 / 1_000_000 = 1.0 → 1
    assert_equal 1, ComputesTtsCost.call(voice_tier: "standard", character_count: 2_500)
  end

  test "standard tier: 2501 chars ceils to 2 cents" do
    # 2501 * 400 / 1_000_000 = 1.0004 → ceil → 2
    assert_equal 2, ComputesTtsCost.call(voice_tier: "standard", character_count: 2_501)
  end

  test "premium tier: 5000 chars = 15 cents" do
    # 5000 * 3000 / 1_000_000 = 15 → 15
    assert_equal 15, ComputesTtsCost.call(voice_tier: "premium", character_count: 5_000)
  end

  test "zero characters costs zero cents" do
    assert_equal 0, ComputesTtsCost.call(voice_tier: "standard", character_count: 0)
    assert_equal 0, ComputesTtsCost.call(voice_tier: "premium", character_count: 0)
  end

  test "negative character counts treated as zero" do
    assert_equal 0, ComputesTtsCost.call(voice_tier: "standard", character_count: -100)
  end

  test "unknown tier raises ArgumentError" do
    assert_raises(ArgumentError) do
      ComputesTtsCost.call(voice_tier: "platinum", character_count: 1_000)
    end
  end

  test "tier argument accepts symbols" do
    assert_equal 1, ComputesTtsCost.call(voice_tier: :standard, character_count: 1_000)
  end
end
