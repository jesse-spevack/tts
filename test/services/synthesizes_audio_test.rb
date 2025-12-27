# frozen_string_literal: true

require "test_helper"

class SynthesizesAudioTest < ActiveSupport::TestCase
  setup do
    Mocktail.replace(Tts::ApiClient)
  end

  test "synthesizes short text with single API call" do
    config = Tts::Config.new(byte_limit: 1000)

    mock_api_client = Mocktail.of(Tts::ApiClient)
    stubs { |m| mock_api_client.call(text: m.any, voice: m.any) }.with { "audio data" }
    stubs { |m| Tts::ApiClient.new(config: m.any) }.with { mock_api_client }

    synthesizer = SynthesizesAudio.new(config: config)

    result = synthesizer.call("Short text.")
    assert_equal "audio data", result
  end

  test "uses chunked synthesizer for long text" do
    config = Tts::Config.new(byte_limit: 10)  # Very small limit to force chunking

    mock_api_client = Mocktail.of(Tts::ApiClient)
    stubs { |m| Tts::ApiClient.new(config: m.any) }.with { mock_api_client }

    synthesizer = SynthesizesAudio.new(config: config)

    # Mock the chunked synthesizer
    mock_chunked = Object.new
    mock_chunked.define_singleton_method(:synthesize) { |chunks, voice| "chunked audio" }
    synthesizer.instance_variable_set(:@chunked_synthesizer, mock_chunked)

    result = synthesizer.call("This is a longer text that will be chunked.")
    assert_equal "chunked audio", result
  end

  test "uses custom voice when provided" do
    config = Tts::Config.new

    mock_api_client = Mocktail.of(Tts::ApiClient)
    stubs { |m| mock_api_client.call(text: m.any, voice: m.any) }.with { "audio" }
    stubs { |m| Tts::ApiClient.new(config: m.any) }.with { mock_api_client }

    synthesizer = SynthesizesAudio.new(config: config)
    synthesizer.call("Hello", voice: "custom-voice")

    calls = Mocktail.calls(mock_api_client, :call)
    assert_equal 1, calls.size
    assert_equal "custom-voice", calls.first.kwargs[:voice]
  end

  test "uses default voice from config when not provided" do
    config = Tts::Config.new(voice_name: "test-default-voice")

    mock_api_client = Mocktail.of(Tts::ApiClient)
    stubs { |m| mock_api_client.call(text: m.any, voice: m.any) }.with { "audio" }
    stubs { |m| Tts::ApiClient.new(config: m.any) }.with { mock_api_client }

    synthesizer = SynthesizesAudio.new(config: config)
    synthesizer.call("Hello")

    calls = Mocktail.calls(mock_api_client, :call)
    assert_equal 1, calls.size
    assert_equal "test-default-voice", calls.first.kwargs[:voice]
  end
end
