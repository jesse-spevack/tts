# frozen_string_literal: true

require "minitest/autorun"
require "logger"
require_relative "../lib/tts/config"

class TestTTSConfiguration < Minitest::Test
  def test_config_uses_defaults
    config = TTS::Config.new

    assert_equal "en-GB-Chirp3-HD-Enceladus", config.voice_name
    assert_equal 1.0, config.speaking_rate
    assert_equal 10, config.thread_pool_size
    assert_equal 850, config.byte_limit
    assert_equal 3, config.max_retries
    assert_equal 300, config.timeout
  end

  def test_config_accepts_custom_values
    custom_config = TTS::Config.new(
      speaking_rate: 2.0,
      thread_pool_size: 5,
      byte_limit: 1000,
      max_retries: 5,
      timeout: 600
    )

    assert_equal 2.0, custom_config.speaking_rate
    assert_equal 5, custom_config.thread_pool_size
    assert_equal 1000, custom_config.byte_limit
    assert_equal 5, custom_config.max_retries
    assert_equal 600, custom_config.timeout
  end

  def test_config_can_be_modified_after_creation
    config = TTS::Config.new
    config.speaking_rate = 2.5
    config.thread_pool_size = 15

    assert_equal 2.5, config.speaking_rate
    assert_equal 15, config.thread_pool_size
  end
end
