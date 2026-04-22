# frozen_string_literal: true

require "test_helper"

class GetsVoiceTierTest < ActiveSupport::TestCase
  # --- catalog hits ---

  test "returns :premium for an episode stamped with a premium google_voice" do
    user = users(:jesse)
    episode = Episode.new(user: user, voice: "en-GB-Chirp3-HD-Enceladus")

    assert_equal :premium, GetsVoiceTier.call(episode: episode)
  end

  test "returns :standard for an episode stamped with a standard google_voice" do
    user = users(:jesse)
    # User prefers a premium voice, but the stamped voice wins.
    user.update!(voice_preference: "callum")

    episode = Episode.new(user: user, voice: "en-GB-Standard-D")

    assert_equal :standard, GetsVoiceTier.call(episode: episode)
  end

  # --- blank effective_voice ---

  test "returns :standard without logging when effective_voice is blank" do
    # No stamped voice and no user — exercise the truly-blank
    # effective_voice path via a stubbed episode double.
    episode = Struct.new(:effective_voice).new(nil)

    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      assert_equal :standard, GetsVoiceTier.call(episode: episode)
    ensure
      Rails.logger = original_logger
    end

    refute_match(/voice_tier_lookup_missed/, output.string)
  end

  test "returns :standard without logging when effective_voice is empty string" do
    episode = Struct.new(:effective_voice).new("")

    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      assert_equal :standard, GetsVoiceTier.call(episode: episode)
    ensure
      Rails.logger = original_logger
    end

    refute_match(/voice_tier_lookup_missed/, output.string)
  end

  # --- catalog miss ---

  test "returns :standard and logs a structured warning when effective_voice is not in catalog" do
    user = users(:jesse)
    episode = Episode.new(user: user, voice: "not-a-real-voice")

    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      assert_equal :standard, GetsVoiceTier.call(episode: episode)
    ensure
      Rails.logger = original_logger
    end

    logs = output.string
    assert_match(/event=voice_tier_lookup_missed/, logs)
    assert_match(/google_voice=not-a-real-voice/, logs)
  end

  # --- legacy row → user fallback via Episode#effective_voice ---

  test "falls back to user.voice when episode.voice is nil (premium)" do
    user = users(:jesse)
    user.update!(voice_preference: "callum") # Chirp3-HD premium

    episode = Episode.new(user: user, voice: nil)

    assert_equal :premium, GetsVoiceTier.call(episode: episode)
  end

  test "falls back to user.voice when episode.voice is nil (standard default)" do
    user = users(:jesse)
    assert_nil user.voice_preference

    episode = Episode.new(user: user, voice: nil)

    # user.voice resolves to DEFAULT_STANDARD (catalog hit).
    assert_equal :standard, GetsVoiceTier.call(episode: episode)
  end

  # --- view-boundary contract: .to_s.capitalize ---

  test "capitalized string output is 'Premium' or 'Standard' for the view" do
    user = users(:jesse)

    premium_episode = Episode.new(user: user, voice: "en-GB-Chirp3-HD-Enceladus")
    assert_equal "Premium", GetsVoiceTier.call(episode: premium_episode).to_s.capitalize

    standard_episode = Episode.new(user: user, voice: "en-GB-Standard-D")
    assert_equal "Standard", GetsVoiceTier.call(episode: standard_episode).to_s.capitalize
  end
end
