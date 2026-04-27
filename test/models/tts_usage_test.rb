require "test_helper"

class TtsUsageTest < ActiveSupport::TestCase
  test "belongs to a polymorphic usable — Episode" do
    usage = TtsUsage.new(
      usable: episodes(:one),
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: 1234,
      cost_cents: 1,
      source: "actual"
    )
    assert usage.valid?
    assert_equal episodes(:one), usage.usable
    assert_equal "Episode", usage.usable_type
  end

  test "belongs to a polymorphic usable — Narration" do
    usage = TtsUsage.new(
      usable: narrations(:one),
      provider: "google",
      voice_id: "en-GB-Chirp3-HD-Enceladus",
      voice_tier: "premium",
      character_count: 5000,
      cost_cents: 15,
      source: "actual"
    )
    assert usage.valid?
    assert_equal narrations(:one), usage.usable
    assert_equal "Narration", usage.usable_type
  end

  test "requires usable" do
    usage = TtsUsage.new(
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )
    assert_not usage.valid?
    assert_includes usage.errors[:usable], "must exist"
  end

  test "requires provider" do
    usage = TtsUsage.new(
      usable: episodes(:one),
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )
    assert_not usage.valid?
    assert_includes usage.errors[:provider], "can't be blank"
  end

  test "requires voice_id" do
    usage = TtsUsage.new(
      usable: episodes(:one),
      provider: "google",
      voice_tier: "standard",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )
    assert_not usage.valid?
    assert_includes usage.errors[:voice_id], "can't be blank"
  end

  test "voice_tier must be standard or premium" do
    usage = TtsUsage.new(
      usable: episodes(:one),
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "gold",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )
    assert_not usage.valid?
    assert_includes usage.errors[:voice_tier], "is not included in the list"
  end

  test "source must be actual or estimate" do
    usage = TtsUsage.new(
      usable: episodes(:one),
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: 100,
      cost_cents: 1,
      source: "guess"
    )
    assert_not usage.valid?
    assert_includes usage.errors[:source], "is not included in the list"
  end

  test "character_count must be a non-negative integer" do
    usage = TtsUsage.new(
      usable: episodes(:one),
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: -1,
      cost_cents: 1,
      source: "actual"
    )
    assert_not usage.valid?
    assert_includes usage.errors[:character_count], "must be greater than or equal to 0"
  end

  test "Episode has_one tts_usage is destroyed on episode destroy" do
    episode = episodes(:one)
    TtsUsage.create!(
      usable: episode,
      provider: "google",
      voice_id: "en-GB-Standard-D",
      voice_tier: "standard",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )

    # Hard-delete (bypassing soft-delete default scope)
    assert_difference -> { TtsUsage.count }, -1 do
      episode.destroy
    end
  end

  test "Narration has_one tts_usage is destroyed on narration destroy" do
    narration = narrations(:one)
    TtsUsage.create!(
      usable: narration,
      provider: "google",
      voice_id: "en-GB-Chirp3-HD-Enceladus",
      voice_tier: "premium",
      character_count: 100,
      cost_cents: 1,
      source: "actual"
    )

    assert_difference -> { TtsUsage.count }, -1 do
      narration.destroy
    end
  end
end
