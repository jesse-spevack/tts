# frozen_string_literal: true

require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  test "STANDARD contains four voices" do
    assert_equal %w[wren felix sloane archer], Voice::STANDARD
  end

  test "CHIRP contains four voices" do
    assert_equal %w[elara callum lark nash], Voice::CHIRP
  end

  test "ALL contains all eight voices" do
    assert_equal 8, Voice::ALL.length
    assert_includes Voice::ALL, "wren"
    assert_includes Voice::ALL, "elara"
  end

  test "for_tier returns STANDARD for free tier" do
    assert_equal Voice::STANDARD, Voice.for_tier("free")
  end

  test "for_tier returns STANDARD for premium tier" do
    assert_equal Voice::STANDARD, Voice.for_tier("premium")
  end

  test "for_tier returns ALL for unlimited tier" do
    assert_equal Voice::ALL, Voice.for_tier("unlimited")
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
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    assert_equal "https://storage.googleapis.com/test-bucket/voices/wren.mp3", Voice.sample_url("wren")
  end
end
