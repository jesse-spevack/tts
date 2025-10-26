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
    @client = TTS::APIClient.new(@config, @logger, client: @mock_google_client)
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
end
