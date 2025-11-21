# frozen_string_literal: true

require "google/cloud/text_to_speech"

class TTS
  # Handles communication with Google Cloud Text-to-Speech API.
  # Provides retry logic for rate limits and transient errors.
  class APIClient
    CONTENT_FILTER_ERROR = "sensitive or harmful content"
    DEADLINE_EXCEEDED_ERROR = "Deadline Exceeded"
    MAX_SAFE_SENTENCE_BYTES = 500

    # Initialize a new API client.
    #
    # @param config [TTS::Config] Configuration object
    # @param logger [Logger] Logger instance
    # @param client [Google::Cloud::TextToSpeech::Client, nil] Optional client for testing
    def initialize(config:, logger:, client: nil)
      @config = config
      @logger = logger

      @client = client || Google::Cloud::TextToSpeech.text_to_speech do |client_config|
        client_config.timeout = @config.timeout
      end
    end

    # Makes a single API call to Google Cloud TTS.
    #
    # @param text [String] The text to convert to speech
    # @param voice [String] Voice name to use
    # @return [String] Binary MP3 audio data
    # @raise [ArgumentError] if text contains sentences that are too long
    # @raise [Google::Cloud::Error] if API call fails
    def call(text:, voice:)
      # Validate sentence length before API call
      validate_sentence_length!(text)

      @logger.info "Making API call (#{text.bytesize} bytes) with voice: #{voice}..."

      response = @client.synthesize_speech(
        input: { text: text },
        voice: build_voice_params(voice),
        audio_config: build_audio_config
      )

      @logger.info "API call successful (#{response.audio_content.bytesize} bytes audio)"
      response.audio_content
    rescue StandardError => e
      # Convert error message to UTF-8 safely to prevent encoding errors when logging
      safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      @logger.error "API call failed: #{safe_message}"
      raise
    end

    # Synthesizes a single chunk with automatic retry logic.
    # Retries on rate limits (ResourceExhaustedError) and timeouts (Deadline Exceeded).
    # Uses exponential backoff for rate limits.
    #
    # @param text [String] The text to synthesize
    # @param voice [String] Voice name to use
    # @param max_retries [Integer] Maximum number of retry attempts
    # @return [String] Binary MP3 audio data
    # @raise [Google::Cloud::ResourceExhaustedError] if max retries exceeded on rate limit
    # @raise [Google::Cloud::Error] if max retries exceeded on timeout or other errors
    def call_with_retry(text:, voice:, max_retries: nil)
      max_retries ||= @config.max_retries
      retries = 0

      begin
        call(text: text, voice: voice)
      rescue Google::Cloud::ResourceExhaustedError => e
        raise unless retries < max_retries

        retries += 1
        wait_time = 2**retries
        @logger.warn "Rate limit hit, waiting #{wait_time}s (retry #{retries}/#{max_retries})"
        sleep(wait_time)
        retry
      rescue Google::Cloud::Error => e
        # Convert error message to UTF-8 safely before checking content
        safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        raise unless retries < max_retries && safe_message.include?(DEADLINE_EXCEEDED_ERROR)

        retries += 1
        @logger.warn "Timeout, retrying (#{retries}/#{max_retries})"
        sleep(1)
        retry
      end
    end

    private

    def validate_sentence_length!(text)
      sentences = text.split(/(?<=[.!?])\s+/)

      sentences.each do |sentence|
        if sentence.bytesize > MAX_SAFE_SENTENCE_BYTES
          raise ArgumentError, "Sentence too long (#{sentence.bytesize} bytes, max #{MAX_SAFE_SENTENCE_BYTES}): #{sentence[0..50]}..."
        end
      end
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
