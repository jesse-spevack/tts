# frozen_string_literal: true

require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  test "ALL contains all twelve voices from CATALOG" do
    assert_equal 12, Voice::ALL.length
    assert_includes Voice::ALL, "wren"
    assert_includes Voice::ALL, "elara"
  end

  test "find returns voice entry for valid key" do
    voice = Voice.find("wren")

    assert_instance_of Voice::Entry, voice
    assert_equal "wren", voice.key
    assert_equal "Wren", voice.name
    assert_equal "British", voice.accent
    assert_equal "Female", voice.gender
    assert_equal "en-GB-Standard-C", voice.google_voice
  end

  test "find includes sample_url" do
    voice = Voice.find("wren")
    expected = "https://storage.googleapis.com/#{AppConfig::Storage::BUCKET}/voices/wren.mp3"
    assert_equal expected, voice.sample_url
  end

  test "find returns nil for invalid key" do
    assert_nil Voice.find("invalid")
  end

  test "chirphd? returns true for ChirpHD voices" do
    assert Voice.find("elara").chirphd?
    assert Voice.find("callum").chirphd?
    assert Voice.find("lark").chirphd?
    assert Voice.find("nash").chirphd?
  end

  test "chirphd? returns false for standard voices" do
    refute Voice.find("wren").chirphd?
    refute Voice.find("felix").chirphd?
  end

  # Tier + pricing (agent-team-nkz.1)

  test "tier returns :premium for ChirpHD voices" do
    %w[elara callum lark nash].each do |key|
      assert_equal :premium, Voice.find(key).tier, "expected #{key} to be :premium"
    end
  end

  test "tier returns :standard for Standard voices" do
    %w[wren felix sloane archer gemma hugo quinn theo].each do |key|
      assert_equal :standard, Voice.find(key).tier, "expected #{key} to be :standard"
    end
  end

  test "premium? matches tier" do
    assert Voice.find("callum").premium?
    refute Voice.find("felix").premium?
  end

  test "standard? matches tier" do
    assert Voice.find("felix").standard?
    refute Voice.find("callum").standard?
  end

  test "price_cents returns PRICE_PREMIUM_CENTS for premium voices" do
    assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, Voice.find("callum").price_cents
  end

  test "price_cents returns PRICE_STANDARD_CENTS for standard voices" do
    assert_equal AppConfig::Mpp::PRICE_STANDARD_CENTS, Voice.find("felix").price_cents
  end

  test "default price_cents values reflect the locked rates (75 standard, 150 premium)" do
    assert_equal 75, AppConfig::Mpp::PRICE_STANDARD_CENTS
    assert_equal 150, AppConfig::Mpp::PRICE_PREMIUM_CENTS
  end

  test "google_voice_for returns google_voice for valid preference" do
    assert_equal "en-GB-Standard-C", Voice.google_voice_for("wren", is_premium: false)
    assert_equal "en-GB-Chirp3-HD-Gacrux", Voice.google_voice_for("elara", is_premium: true)
  end

  test "google_voice_for returns DEFAULT_STANDARD when preference is nil and not premium" do
    assert_equal Voice::DEFAULT_STANDARD, Voice.google_voice_for(nil, is_premium: false)
  end

  test "google_voice_for returns DEFAULT_CHIRP when preference is nil and premium" do
    assert_equal Voice::DEFAULT_CHIRP, Voice.google_voice_for(nil, is_premium: true)
  end

  test "google_voice_for returns DEFAULT_STANDARD when preference is empty string and not premium" do
    assert_equal Voice::DEFAULT_STANDARD, Voice.google_voice_for("", is_premium: false)
  end

  test "google_voice_for returns DEFAULT_CHIRP when preference is empty string and premium" do
    assert_equal Voice::DEFAULT_CHIRP, Voice.google_voice_for("", is_premium: true)
  end

  test "google_voice_for returns default when preference is invalid and not premium" do
    assert_equal Voice::DEFAULT_STANDARD, Voice.google_voice_for("invalid_voice", is_premium: false)
  end

  test "google_voice_for returns default when preference is invalid and premium" do
    assert_equal Voice::DEFAULT_CHIRP, Voice.google_voice_for("invalid_voice", is_premium: true)
  end

  # tier_for reverse lookup (agent-team-cue3)

  test "tier_for returns :premium for a premium google_voice" do
    assert_equal :premium, Voice.tier_for("en-GB-Chirp3-HD-Enceladus")
  end

  test "tier_for returns :standard for a standard google_voice" do
    assert_equal :standard, Voice.tier_for("en-GB-Standard-D")
  end

  test "tier_for returns nil and stays silent for blank input" do
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      assert_nil Voice.tier_for(nil)
      assert_nil Voice.tier_for("")
    ensure
      Rails.logger = original_logger
    end

    refute_match(/voice_tier_lookup_missed/, output.string)
  end

  test "tier_for returns nil and logs a structured warning on catalog miss" do
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      assert_nil Voice.tier_for("not-a-real-voice")
    ensure
      Rails.logger = original_logger
    end

    logs = output.string
    assert_match(/event=voice_tier_lookup_missed/, logs)
    assert_match(/google_voice=not-a-real-voice/, logs)
  end
end
