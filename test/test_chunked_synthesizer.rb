# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "logger"
require_relative "../lib/tts/config"
require_relative "../lib/tts/chunked_synthesizer"

class TestChunkedSynthesizer < Minitest::Test
  def setup
    @config = TTS::Config.new(thread_pool_size: 2)
    @logger = Logger.new(File::NULL)
    @mock_api_client = Minitest::Mock.new
    @synthesizer = TTS::ChunkedSynthesizer.new(api_client: @mock_api_client, config: @config, logger: @logger)
  end

  def test_synthesize_single_chunk
    chunks = ["Hello, world!"]
    voice = "en-GB-Chirp3-HD-Enceladus"

    @mock_api_client.expect :call_with_retry, "audio1" do |text:, voice:, max_retries:|
      assert_equal "Hello, world!", text
      assert_equal "en-GB-Chirp3-HD-Enceladus", voice
      assert_equal 3, max_retries
      true
    end

    result = @synthesizer.synthesize(chunks, voice)

    assert_equal "audio1", result
    @mock_api_client.verify
  end

  def test_synthesize_multiple_chunks_concatenates
    # Use single thread to ensure deterministic ordering in test
    config = TTS::Config.new(thread_pool_size: 1)
    synthesizer = TTS::ChunkedSynthesizer.new(api_client: @mock_api_client, config: config, logger: @logger)

    chunks = ["First chunk.", "Second chunk.", "Third chunk."]
    voice = "en-GB-Chirp3-HD-Enceladus"

    @mock_api_client.expect :call_with_retry, "audio1" do |**_kwargs|
      true
    end
    @mock_api_client.expect :call_with_retry, "audio2" do |**_kwargs|
      true
    end
    @mock_api_client.expect :call_with_retry, "audio3" do |**_kwargs|
      true
    end

    result = synthesizer.synthesize(chunks, voice)

    assert_equal "audio1audio2audio3", result
    @mock_api_client.verify
  end

  def test_synthesize_skips_content_filtered_chunks
    chunks = ["Safe chunk.", "Filtered chunk.", "Another safe chunk."]
    voice = "en-GB-Chirp3-HD-Enceladus"

    @mock_api_client.expect :call_with_retry, "audio1" do |**_kwargs|
      true
    end

    @mock_api_client.expect :call_with_retry, nil do |**_kwargs|
      raise StandardError, "Error with sensitive or harmful content"
    end

    @mock_api_client.expect :call_with_retry, "audio3" do |**_kwargs|
      true
    end

    result = @synthesizer.synthesize(chunks, voice)

    assert_equal "audio1audio3", result
    @mock_api_client.verify
  end

  def test_synthesize_raises_on_non_filter_errors
    chunks = ["Chunk 1."]
    voice = "en-GB-Chirp3-HD-Enceladus"

    @mock_api_client.expect :call_with_retry, nil do |**_kwargs|
      raise StandardError, "Network error"
    end

    error = assert_raises(StandardError) do
      @synthesizer.synthesize(chunks, voice)
    end

    assert_equal "Network error", error.message
  end

  def test_synthesize_handles_empty_chunks_array
    result = @synthesizer.synthesize([], "en-GB-Chirp3-HD-Enceladus")

    assert_equal "", result
  end

  def test_synthesize_maintains_chunk_order
    # Use single thread to ensure deterministic ordering in test
    config = TTS::Config.new(thread_pool_size: 1)
    synthesizer = TTS::ChunkedSynthesizer.new(api_client: @mock_api_client, config: config, logger: @logger)

    chunks = ["Chunk 1.", "Chunk 2.", "Chunk 3.", "Chunk 4."]
    voice = "en-GB-Chirp3-HD-Enceladus"

    # Return audio in specific order
    4.times do |i|
      @mock_api_client.expect :call_with_retry, "audio#{i + 1}" do |**_kwargs|
        true
      end
    end

    result = synthesizer.synthesize(chunks, voice)

    assert_equal "audio1audio2audio3audio4", result
    @mock_api_client.verify
  end
end
