# frozen_string_literal: true

require "test_helper"

class Tts::ConfigTest < ActiveSupport::TestCase
  test "initializes with default values" do
    config = Tts::Config.new

    assert_equal "en-GB-Chirp3-HD-Enceladus", config.voice_name
    assert_equal "en-GB", config.language_code
    assert_equal 1.0, config.speaking_rate
    assert_equal 0.0, config.pitch
    assert_equal "MP3", config.audio_encoding
    assert_equal 300, config.timeout
    assert_equal 3, config.max_retries
    assert_equal 10, config.thread_pool_size
    assert_equal 850, config.byte_limit
  end

  test "accepts custom values" do
    config = Tts::Config.new(
      voice_name: "en-US-Wavenet-A",
      speaking_rate: 1.5,
      thread_pool_size: 5
    )

    assert_equal "en-US-Wavenet-A", config.voice_name
    assert_equal 1.5, config.speaking_rate
    assert_equal 5, config.thread_pool_size
  end

  test "validates speaking_rate range" do
    assert_raises(ArgumentError) { Tts::Config.new(speaking_rate: 0.1) }
    assert_raises(ArgumentError) { Tts::Config.new(speaking_rate: 5.0) }
    assert_nothing_raised { Tts::Config.new(speaking_rate: 0.25) }
    assert_nothing_raised { Tts::Config.new(speaking_rate: 4.0) }
  end

  test "validates pitch range" do
    assert_raises(ArgumentError) { Tts::Config.new(pitch: -25.0) }
    assert_raises(ArgumentError) { Tts::Config.new(pitch: 25.0) }
    assert_nothing_raised { Tts::Config.new(pitch: -20.0) }
    assert_nothing_raised { Tts::Config.new(pitch: 20.0) }
  end

  test "validates thread_pool_size is positive integer" do
    assert_raises(ArgumentError) { Tts::Config.new(thread_pool_size: 0) }
    assert_raises(ArgumentError) { Tts::Config.new(thread_pool_size: -1) }
    assert_nothing_raised { Tts::Config.new(thread_pool_size: 1) }
  end

  test "validates byte_limit is positive integer" do
    assert_raises(ArgumentError) { Tts::Config.new(byte_limit: 0) }
    assert_raises(ArgumentError) { Tts::Config.new(byte_limit: -100) }
    assert_nothing_raised { Tts::Config.new(byte_limit: 100) }
  end

  test "validates max_retries is non-negative integer" do
    assert_raises(ArgumentError) { Tts::Config.new(max_retries: -1) }
    assert_nothing_raised { Tts::Config.new(max_retries: 0) }
    assert_nothing_raised { Tts::Config.new(max_retries: 5) }
  end
end
