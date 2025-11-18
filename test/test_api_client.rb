# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "logger"
require_relative "../lib/tts/config"
require_relative "../lib/tts/api_client"

class TestAPIClient < Minitest::Test
  def setup
    @config = TTS::Config.new
    @logger = Logger.new(File::NULL)
    @mock_google_client = Minitest::Mock.new
    @client = TTS::APIClient.new(config: @config, logger: @logger, client: @mock_google_client)
  end

  def test_call_makes_successful_api_request
    # Create a simple response object
    response = Struct.new(:audio_content).new("fake_audio_data")

    @mock_google_client.expect :synthesize_speech, response do |input:, voice:, **|
      assert_equal "Hello, world!", input[:text]
      assert_equal "en-GB-Chirp3-HD-Enceladus", voice[:name]
      true
    end

    result = @client.call(text: "Hello, world!", voice: "en-GB-Chirp3-HD-Enceladus")

    assert_equal "fake_audio_data", result
    @mock_google_client.verify
  end

  def test_call_with_retry_uses_default_max_retries
    response = Struct.new(:audio_content).new("fake_audio_data")

    @mock_google_client.expect :synthesize_speech, response do |**_kwargs|
      true
    end

    result = @client.call_with_retry(text: "Hello!", voice: "en-GB-Chirp3-HD-Enceladus")

    assert_equal "fake_audio_data", result
    @mock_google_client.verify
  end

  def test_call_with_retry_uses_custom_max_retries
    response = Struct.new(:audio_content).new("fake_audio_data")

    @mock_google_client.expect :synthesize_speech, response do |**_kwargs|
      true
    end

    result = @client.call_with_retry(text: "Hello!", voice: "en-GB-Chirp3-HD-Enceladus", max_retries: 5)

    assert_equal "fake_audio_data", result
    @mock_google_client.verify
  end

  def test_handles_binary_error_messages_without_encoding_errors
    # Test that binary error messages don't cause encoding errors when logged
    # Use a real logger that writes to a StringIO to catch encoding issues
    log_output = StringIO.new
    logger = Logger.new(log_output)
    client = TTS::APIClient.new(config: @config, logger: logger, client: @mock_google_client)

    binary_message = +"API error: \xFF\xFE binary data"
    binary_message.force_encoding("ASCII-8BIT")
    error = StandardError.new(binary_message)

    @mock_google_client.expect :synthesize_speech, nil do |**_kwargs|
      raise error
    end

    # This should raise the original error, NOT an Encoding::CompatibilityError
    raised_error = assert_raises(StandardError) do
      client.call(text: "Hello!", voice: "en-GB-Chirp3-HD-Enceladus")
    end

    # Verify we got the original error, not an encoding error
    refute_instance_of Encoding::CompatibilityError, raised_error
  end
end
