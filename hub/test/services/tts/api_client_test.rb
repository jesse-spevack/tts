# frozen_string_literal: true

require "test_helper"

class Tts::ApiClientTest < ActiveSupport::TestCase
  setup do
    @config = Tts::Config.new
  end

  test "builds correct voice params from config" do
    api_client = Tts::ApiClient.new(config: @config)

    voice_params = api_client.send(:build_voice_params, "test-voice")

    assert_equal "en-GB", voice_params[:language_code]
    assert_equal "test-voice", voice_params[:name]
  end

  test "builds correct audio config from config" do
    api_client = Tts::ApiClient.new(config: @config)

    audio_config = api_client.send(:build_audio_config)

    assert_equal "MP3", audio_config[:audio_encoding]
    assert_equal 1.0, audio_config[:speaking_rate]
    assert_equal 0.0, audio_config[:pitch]
  end

  test "uses custom speaking rate and pitch" do
    config = Tts::Config.new(speaking_rate: 1.5, pitch: 2.0)
    api_client = Tts::ApiClient.new(config: config)

    audio_config = api_client.send(:build_audio_config)

    assert_equal 1.5, audio_config[:speaking_rate]
    assert_equal 2.0, audio_config[:pitch]
  end
end
