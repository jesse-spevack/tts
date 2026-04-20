# frozen_string_literal: true

require "test_helper"

class CalculatesEpisodeCreditCostTest < ActiveSupport::TestCase
  # Voice catalog: 'felix' is Standard, 'callum' is Premium (ChirpHD).
  # See AppConfig::Tiers::CHIRPHD_VOICES and Voice::CATALOG.
  setup do
    @standard_voice = Voice.find("felix")
    @premium_voice = Voice.find("callum")
  end

  # --- Four quadrants (length x voice) ---------------------------------------

  test "short source with Standard voice costs 1 credit" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 15_000,
      voice: @standard_voice
    )

    assert_equal 1, result
  end

  test "short source with Premium voice costs 1 credit" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 15_000,
      voice: @premium_voice
    )

    assert_equal 1, result
  end

  test "long source with Standard voice costs 1 credit" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 30_000,
      voice: @standard_voice
    )

    assert_equal 1, result
  end

  test "long source with Premium voice costs 2 credits" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 30_000,
      voice: @premium_voice
    )

    assert_equal 2, result
  end

  # --- Boundary cases --------------------------------------------------------

  test "exactly 20000 chars with Premium voice costs 1 credit (boundary: <=20k stays at 1)" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 20_000,
      voice: @premium_voice
    )

    assert_equal 1, result
  end

  test "20001 chars with Premium voice costs 2 credits (>20k triggers)" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 20_001,
      voice: @premium_voice
    )

    assert_equal 2, result
  end

  test "20001 chars with Standard voice costs 1 credit" do
    result = CalculatesEpisodeCreditCost.call(
      source_text_length: 20_001,
      voice: @standard_voice
    )

    assert_equal 1, result
  end
end
