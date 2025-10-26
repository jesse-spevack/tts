# frozen_string_literal: true

class TTS
  # Configuration class for TTS settings.
  #
  # Provides centralized configuration for Text-to-Speech operations with
  # sensible defaults and validation.
  #
  # @example Using default configuration
  #   config = TTS::Config.new
  #   config.speaking_rate  # => 1.5
  #   config.voice_name     # => "en-GB-Chirp3-HD-Enceladus"
  #
  # @example Custom configuration
  #   config = TTS::Config.new(
  #     speaking_rate: 2.0,
  #     thread_pool_size: 5,
  #     byte_limit: 1000
  #   )
  #
  # @example Modifying after initialization
  #   config = TTS::Config.new
  #   config.speaking_rate = 1.25
  #   config.thread_pool_size = 20
  #
  # Configuration Options:
  # - voice_name: Voice identifier (default: "en-GB-Chirp3-HD-Enceladus")
  # - language_code: Language code (default: "en-GB")
  # - speaking_rate: Speech rate, 0.25-4.0 (default: 1.5)
  # - pitch: Voice pitch, -20.0 to 20.0 (default: 0.0)
  # - audio_encoding: Output format (default: "MP3")
  # - timeout: API timeout in seconds (default: 300)
  # - max_retries: Retry attempts for failed requests (default: 3)
  # - thread_pool_size: Concurrent threads for chunking (default: 10)
  # - byte_limit: Maximum bytes per API request (default: 850, Google TTS byte limit - can be overridden via config)
  class Config
    attr_accessor :voice_name, :language_code, :speaking_rate, :pitch, :audio_encoding, :timeout, :max_retries,
                  :thread_pool_size, :byte_limit

    def initialize(
      voice_name: "en-GB-Chirp3-HD-Enceladus",
      language_code: "en-GB",
      speaking_rate: 1.5,
      pitch: 0.0,
      audio_encoding: "MP3",
      timeout: 300,
      max_retries: 3,
      thread_pool_size: 10,
      byte_limit: 850
    )
      @voice_name = voice_name
      @language_code = language_code
      @speaking_rate = speaking_rate
      @pitch = pitch
      @audio_encoding = audio_encoding
      @timeout = timeout
      @max_retries = max_retries
      @thread_pool_size = thread_pool_size
      @byte_limit = byte_limit

      validate!
    end

    private

    def validate!
      if !@speaking_rate.is_a?(Numeric) || @speaking_rate < 0.25 || @speaking_rate > 4.0
        raise ArgumentError, "speaking_rate must be between 0.25 and 4.0, got #{@speaking_rate}"
      end

      if !@pitch.is_a?(Numeric) || @pitch < -20.0 || @pitch > 20.0
        raise ArgumentError, "pitch must be between -20.0 and 20.0, got #{@pitch}"
      end

      if !@thread_pool_size.is_a?(Integer) || @thread_pool_size <= 0
        raise ArgumentError, "thread_pool_size must be a positive integer, got #{@thread_pool_size}"
      end

      if !@byte_limit.is_a?(Integer) || @byte_limit <= 0
        raise ArgumentError, "byte_limit must be a positive integer, got #{@byte_limit}"
      end

      return unless !@max_retries.is_a?(Integer) || @max_retries.negative?

      raise ArgumentError, "max_retries must be a non-negative integer, got #{@max_retries}"
    end
  end
end
