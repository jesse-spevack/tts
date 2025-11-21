# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/tts/api_client"
require_relative "../lib/tts/config"
require "logger"
require "ostruct"

class TestAPIClientValidation < Minitest::Test
  def test_raises_on_long_sentence_in_text
    config = TTS::Config.new
    logger = Logger.new(nil) # Silent logger

    client = TTS::APIClient.new(config: config, logger: logger, client: MockTTSClient.new)

    long_sentence = "A" * 600 + "."

    error = assert_raises(ArgumentError) do
      client.call(text: long_sentence, voice: config.voice_name)
    end

    assert_match(/sentence too long/i, error.message)
  end

  def test_accepts_normal_text
    config = TTS::Config.new
    logger = Logger.new(nil)
    mock_client = MockTTSClient.new

    client = TTS::APIClient.new(config: config, logger: logger, client: mock_client)

    # Should not raise
    result = client.call(text: "Normal sentence.", voice: config.voice_name)
    assert_equal "mock audio data", result
  end
end

class MockTTSClient
  def synthesize_speech(*)
    OpenStruct.new(audio_content: "mock audio data")
  end
end
