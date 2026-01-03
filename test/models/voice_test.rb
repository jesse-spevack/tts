# frozen_string_literal: true

require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  test "ALL contains all eight voices from CATALOG" do
    assert_equal 8, Voice::ALL.length
    assert_includes Voice::ALL, "wren"
    assert_includes Voice::ALL, "elara"
  end

  test "find returns voice data for valid key" do
    voice = Voice.find("wren")

    assert_equal "Wren", voice[:name]
    assert_equal "British", voice[:accent]
    assert_equal "Female", voice[:gender]
    assert_equal "en-GB-Standard-C", voice[:google_voice]
  end

  test "find returns nil for invalid key" do
    assert_nil Voice.find("invalid")
  end

  test "sample_url returns GCS URL for voice" do
    expected = "https://storage.googleapis.com/#{AppConfig::Storage::BUCKET}/voices/wren.mp3"
    assert_equal expected, Voice.sample_url("wren")
  end

  test "google_voice_for returns google_voice for valid preference" do
    assert_equal "en-GB-Standard-C", Voice.google_voice_for("wren", is_unlimited: false)
    assert_equal "en-GB-Chirp3-HD-Gacrux", Voice.google_voice_for("elara", is_unlimited: true)
  end

  test "google_voice_for returns DEFAULT_STANDARD when preference is nil and not unlimited" do
    assert_equal Voice::DEFAULT_STANDARD, Voice.google_voice_for(nil, is_unlimited: false)
  end

  test "google_voice_for returns DEFAULT_CHIRP when preference is nil and unlimited" do
    assert_equal Voice::DEFAULT_CHIRP, Voice.google_voice_for(nil, is_unlimited: true)
  end

  test "google_voice_for returns DEFAULT_STANDARD when preference is empty string and not unlimited" do
    assert_equal Voice::DEFAULT_STANDARD, Voice.google_voice_for("", is_unlimited: false)
  end

  test "google_voice_for returns DEFAULT_CHIRP when preference is empty string and unlimited" do
    assert_equal Voice::DEFAULT_CHIRP, Voice.google_voice_for("", is_unlimited: true)
  end

  test "google_voice_for returns default when preference is invalid and not unlimited" do
    assert_equal Voice::DEFAULT_STANDARD, Voice.google_voice_for("invalid_voice", is_unlimited: false)
  end

  test "google_voice_for returns default when preference is invalid and unlimited" do
    assert_equal Voice::DEFAULT_CHIRP, Voice.google_voice_for("invalid_voice", is_unlimited: true)
  end
end
