# frozen_string_literal: true

require "test_helper"

class RecordsTtsUsageTest < ActiveSupport::TestCase
  test "creates TtsUsage row with source=actual by default" do
    episode = episodes(:one)

    assert_difference -> { TtsUsage.count }, 1 do
      RecordsTtsUsage.call(
        usable: episode,
        voice_id: "en-GB-Standard-D",
        character_count: 1_500
      )
    end

    usage = TtsUsage.last
    assert_equal episode, usage.usable
    assert_equal "google", usage.provider
    assert_equal "en-GB-Standard-D", usage.voice_id
    assert_equal "standard", usage.voice_tier
    assert_equal 1_500, usage.character_count
    assert_equal "actual", usage.source
  end

  test "infers premium tier from Chirp3-HD voice id" do
    narration = narrations(:one)

    RecordsTtsUsage.call(
      usable: narration,
      voice_id: "en-GB-Chirp3-HD-Enceladus",
      character_count: 2_000
    )

    usage = TtsUsage.last
    assert_equal "premium", usage.voice_tier
  end

  test "computes cost_cents via ComputesTtsCost helper" do
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-US-Chirp3-HD-Callirrhoe",
      character_count: 1_000
    )

    usage = TtsUsage.last
    # premium @ 1000 chars: 1000 * 3000 / 1_000_000 = 3
    assert_equal 3, usage.cost_cents
  end

  test "standard tier 2501 chars ceils to 2 cents" do
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 2_501
    )

    assert_equal 2, TtsUsage.last.cost_cents
  end

  test "accepts explicit source override for future backfills" do
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 1_000,
      source: "estimate"
    )

    assert_equal "estimate", TtsUsage.last.source
  end

  test "returns the created usage record" do
    episode = episodes(:one)

    result = RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 500
    )

    assert_instance_of TtsUsage, result
    assert_equal episode, result.usable
  end
end
