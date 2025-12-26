# frozen_string_literal: true

require "test_helper"

class TtsSynthesizerTest < ActiveSupport::TestCase
  test "synthesizes short text with single API call" do
    config = Tts::Config.new(byte_limit: 1000)

    mock_api_client = Object.new
    mock_api_client.define_singleton_method(:call) { |text:, voice:| "audio data" }

    synthesizer = Tts::Synthesizer.new(config: config)
    synthesizer.instance_variable_set(:@api_client, mock_api_client)

    result = synthesizer.synthesize("Short text.")
    assert_equal "audio data", result
  end

  test "uses chunked synthesizer for long text" do
    config = Tts::Config.new(byte_limit: 10)  # Very small limit to force chunking

    synthesizer = Tts::Synthesizer.new(config: config)

    # Mock the chunked synthesizer
    mock_chunked = Object.new
    mock_chunked.define_singleton_method(:synthesize) { |chunks, voice| "chunked audio" }
    synthesizer.instance_variable_set(:@chunked_synthesizer, mock_chunked)

    result = synthesizer.synthesize("This is a longer text that will be chunked.")
    assert_equal "chunked audio", result
  end

  test "uses custom voice when provided" do
    config = Tts::Config.new

    mock_api_client = Object.new
    voice_used = nil
    mock_api_client.define_singleton_method(:call) do |text:, voice:|
      voice_used = voice
      "audio"
    end

    synthesizer = Tts::Synthesizer.new(config: config)
    synthesizer.instance_variable_set(:@api_client, mock_api_client)

    synthesizer.synthesize("Hello", voice: "custom-voice")
    assert_equal "custom-voice", voice_used
  end

  test "uses default voice from config when not provided" do
    config = Tts::Config.new(voice_name: "test-default-voice")

    mock_api_client = Object.new
    voice_used = nil
    mock_api_client.define_singleton_method(:call) do |text:, voice:|
      voice_used = voice
      "audio"
    end

    synthesizer = Tts::Synthesizer.new(config: config)
    synthesizer.instance_variable_set(:@api_client, mock_api_client)

    synthesizer.synthesize("Hello")
    assert_equal "test-default-voice", voice_used
  end
end
