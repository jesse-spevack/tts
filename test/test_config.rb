# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/tts/config"

class TestConfig < Minitest::Test
  def test_default_configuration
    config = TTS::Config.new

    assert_equal "en-GB-Chirp3-HD-Enceladus", config.voice_name
    assert_equal "en-GB", config.language_code
    assert_equal 1.5, config.speaking_rate
    assert_equal 0.0, config.pitch
    assert_equal "MP3", config.audio_encoding
    assert_equal 300, config.timeout
    assert_equal 3, config.max_retries
    assert_equal 10, config.thread_pool_size
    assert_equal 850, config.byte_limit
  end

  def test_custom_configuration_with_keyword_arguments
    config = TTS::Config.new(
      speaking_rate: 2.0,
      thread_pool_size: 5,
      byte_limit: 1000
    )

    assert_equal 2.0, config.speaking_rate
    assert_equal 5, config.thread_pool_size
    assert_equal 1000, config.byte_limit
    assert_equal "en-GB-Chirp3-HD-Enceladus", config.voice_name # default still applies
  end

  def test_attribute_setters
    config = TTS::Config.new
    config.speaking_rate = 1.25
    config.thread_pool_size = 20

    assert_equal 1.25, config.speaking_rate
    assert_equal 20, config.thread_pool_size
  end

  def test_speaking_rate_validation_too_low
    error = assert_raises(ArgumentError) do
      TTS::Config.new(speaking_rate: 0.1)
    end
    assert_match(/speaking_rate must be between 0.25 and 4.0/, error.message)
  end

  def test_speaking_rate_validation_too_high
    error = assert_raises(ArgumentError) do
      TTS::Config.new(speaking_rate: 5.0)
    end
    assert_match(/speaking_rate must be between 0.25 and 4.0/, error.message)
  end

  def test_speaking_rate_validation_not_numeric
    error = assert_raises(ArgumentError) do
      TTS::Config.new(speaking_rate: "fast")
    end
    assert_match(/speaking_rate must be between 0.25 and 4.0/, error.message)
  end

  def test_pitch_validation_too_low
    error = assert_raises(ArgumentError) do
      TTS::Config.new(pitch: -25.0)
    end
    assert_match(/pitch must be between -20.0 and 20.0/, error.message)
  end

  def test_pitch_validation_too_high
    error = assert_raises(ArgumentError) do
      TTS::Config.new(pitch: 25.0)
    end
    assert_match(/pitch must be between -20.0 and 20.0/, error.message)
  end

  def test_thread_pool_size_validation_zero
    error = assert_raises(ArgumentError) do
      TTS::Config.new(thread_pool_size: 0)
    end
    assert_match(/thread_pool_size must be a positive integer/, error.message)
  end

  def test_thread_pool_size_validation_negative
    error = assert_raises(ArgumentError) do
      TTS::Config.new(thread_pool_size: -5)
    end
    assert_match(/thread_pool_size must be a positive integer/, error.message)
  end

  def test_thread_pool_size_validation_not_integer
    error = assert_raises(ArgumentError) do
      TTS::Config.new(thread_pool_size: 5.5)
    end
    assert_match(/thread_pool_size must be a positive integer/, error.message)
  end

  def test_byte_limit_validation_zero
    error = assert_raises(ArgumentError) do
      TTS::Config.new(byte_limit: 0)
    end
    assert_match(/byte_limit must be a positive integer/, error.message)
  end

  def test_byte_limit_validation_negative
    error = assert_raises(ArgumentError) do
      TTS::Config.new(byte_limit: -100)
    end
    assert_match(/byte_limit must be a positive integer/, error.message)
  end

  def test_max_retries_validation_negative
    error = assert_raises(ArgumentError) do
      TTS::Config.new(max_retries: -1)
    end
    assert_match(/max_retries must be a non-negative integer/, error.message)
  end

  def test_max_retries_validation_accepts_zero
    config = TTS::Config.new(max_retries: 0)
    assert_equal 0, config.max_retries
  end

  def test_max_retries_validation_not_integer
    error = assert_raises(ArgumentError) do
      TTS::Config.new(max_retries: 2.5)
    end
    assert_match(/max_retries must be a non-negative integer/, error.message)
  end

  def test_valid_edge_cases
    config = TTS::Config.new(
      speaking_rate: 0.25,
      pitch: -20.0,
      thread_pool_size: 1,
      byte_limit: 1,
      max_retries: 0
    )

    assert_equal 0.25, config.speaking_rate
    assert_equal(-20.0, config.pitch)
    assert_equal 1, config.thread_pool_size
    assert_equal 1, config.byte_limit
    assert_equal 0, config.max_retries
  end
end
