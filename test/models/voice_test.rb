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
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    assert_equal "https://storage.googleapis.com/test-bucket/voices/wren.mp3", Voice.sample_url("wren")
  end
end
