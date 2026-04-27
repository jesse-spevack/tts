# frozen_string_literal: true

require "test_helper"

class GetsVoiceTierTest < ActiveSupport::TestCase
  # --- .call(episode:) — view boundary returns :symbol ---

  test "returns :premium for an episode stamped with a premium google_voice" do
    user = users(:jesse)
    episode = Episode.new(user: user, voice: "en-GB-Chirp3-HD-Enceladus")

    assert_equal :premium, GetsVoiceTier.call(episode: episode)
  end

  test "returns :standard for an episode stamped with a standard google_voice" do
    user = users(:jesse)
    user.update!(voice_preference: "callum") # premium preference overridden by stamped voice
    episode = Episode.new(user: user, voice: "en-GB-Standard-D")

    assert_equal :standard, GetsVoiceTier.call(episode: episode)
  end

  test "falls back to user.voice when episode.voice is nil (premium)" do
    user = users(:jesse)
    user.update!(voice_preference: "callum")
    episode = Episode.new(user: user, voice: nil)

    assert_equal :premium, GetsVoiceTier.call(episode: episode)
  end

  test "falls back to user.voice when episode.voice is nil (standard default)" do
    user = users(:jesse)
    assert_nil user.voice_preference
    episode = Episode.new(user: user, voice: nil)

    assert_equal :standard, GetsVoiceTier.call(episode: episode)
  end

  test "capitalized string output is 'Premium' or 'Standard' for the view" do
    user = users(:jesse)

    premium = Episode.new(user: user, voice: "en-GB-Chirp3-HD-Enceladus")
    standard = Episode.new(user: user, voice: "en-GB-Standard-D")

    assert_equal "Premium", GetsVoiceTier.call(episode: premium).to_s.capitalize
    assert_equal "Standard", GetsVoiceTier.call(episode: standard).to_s.capitalize
  end

  # --- .tier_for(google_voice_id) — string boundary used by RecordsTtsUsage ---

  test "tier_for returns 'premium' for a Chirp3-HD voice" do
    assert_equal "premium", GetsVoiceTier.tier_for("en-GB-Chirp3-HD-Enceladus")
    assert_equal "premium", GetsVoiceTier.tier_for("en-US-Chirp3-HD-Callirrhoe")
  end

  test "tier_for returns 'standard' for a Standard voice" do
    assert_equal "standard", GetsVoiceTier.tier_for("en-GB-Standard-D")
    assert_equal "standard", GetsVoiceTier.tier_for("en-US-Standard-C")
  end

  test "tier_for round-trips every Voice::CATALOG entry" do
    # Guard against drift between the catalog and the reverse index.
    Voice::CATALOG.each_key do |key|
      voice = Voice.find(key)
      assert_equal voice.tier.to_s, GetsVoiceTier.tier_for(voice.google_voice),
        "Expected #{voice.google_voice} (#{key}) to resolve to #{voice.tier}"
    end
  end

  test "tier_for returns 'standard' and logs a structured warning on a catalog miss" do
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      assert_equal "standard", GetsVoiceTier.tier_for("en-US-Neural2-F")
    ensure
      Rails.logger = original_logger
    end

    assert_match(/event=tts_tier_lookup_missed/, output.string)
    assert_match(/google_voice=en-US-Neural2-F/, output.string)
  end
end
