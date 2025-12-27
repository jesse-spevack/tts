# frozen_string_literal: true

require "google/cloud/text_to_speech"

module Tts
  # Handles communication with Google Cloud Text-to-Speech API.
  class ApiClient
    CONTENT_FILTER_ERROR = "sensitive or harmful content"
    DEADLINE_EXCEEDED_ERROR = "Deadline Exceeded"

    def initialize(config:)
      @config = config
      @client = Google::Cloud::TextToSpeech.text_to_speech do |client_config|
        client_config.timeout = @config.timeout
      end
    end

    def call(text:, voice:)
      max_retries = @config.max_retries
      retries = 0

      begin
        make_request(text: text, voice: voice)
      rescue Google::Cloud::ResourceExhaustedError
        raise unless retries < max_retries

        retries += 1
        wait_time = 2**retries
        Rails.logger.warn "[TTS] Rate limit hit, waiting #{wait_time}s (retry #{retries}/#{max_retries})"
        sleep(wait_time)
        retry
      rescue Google::Cloud::Error => e
        safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        raise unless retries < max_retries && safe_message.include?(DEADLINE_EXCEEDED_ERROR)

        retries += 1
        Rails.logger.warn "[TTS] Timeout, retrying (#{retries}/#{max_retries})"
        sleep(1)
        retry
      end
    end

    private

    def make_request(text:, voice:)
      Rails.logger.info "[TTS] Making API call (#{text.bytesize} bytes) with voice: #{voice}..."

      response = @client.synthesize_speech(
        input: { text: text },
        voice: build_voice_params(voice),
        audio_config: build_audio_config
      )

      Rails.logger.info "[TTS] API call successful (#{response.audio_content.bytesize} bytes audio)"
      response.audio_content
    rescue StandardError => e
      safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      Rails.logger.error "[TTS] API call failed: #{safe_message}"
      raise
    end

    def build_voice_params(voice)
      {
        language_code: @config.language_code,
        name: voice
      }
    end

    def build_audio_config
      {
        audio_encoding: @config.audio_encoding,
        speaking_rate: @config.speaking_rate,
        pitch: @config.pitch
      }
    end
  end
end
