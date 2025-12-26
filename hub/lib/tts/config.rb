# frozen_string_literal: true

module Tts
  # Configuration class for TTS settings.
  class Config
    attr_accessor :voice_name, :language_code, :speaking_rate, :pitch, :audio_encoding, :timeout, :max_retries,
                  :thread_pool_size, :byte_limit

    def initialize(
      voice_name: "en-GB-Chirp3-HD-Enceladus",
      language_code: "en-GB",
      speaking_rate: 1.0,
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

    def valid_speaking_rate?
      @speaking_rate.is_a?(Numeric) && @speaking_rate >= 0.25 && @speaking_rate <= 4.0
    end

    def valid_pitch?
      @pitch.is_a?(Numeric) && @pitch >= -20.0 && @pitch <= 20.0
    end

    def valid_thread_pool_size?
      @thread_pool_size.is_a?(Integer) && @thread_pool_size.positive?
    end

    def valid_byte_limit?
      @byte_limit.is_a?(Integer) && @byte_limit.positive?
    end

    def valid_max_retries?
      @max_retries.is_a?(Integer) && !@max_retries.negative?
    end

    def validate!
      unless valid_speaking_rate?
        raise ArgumentError,
              "speaking_rate must be between 0.25 and 4.0, got #{@speaking_rate}"
      end
      raise ArgumentError, "pitch must be between -20.0 and 20.0, got #{@pitch}" unless valid_pitch?

      unless valid_thread_pool_size?
        raise ArgumentError,
              "thread_pool_size must be a positive integer, got #{@thread_pool_size}"
      end
      raise ArgumentError, "byte_limit must be a positive integer, got #{@byte_limit}" unless valid_byte_limit?
      raise ArgumentError, "max_retries must be a non-negative integer, got #{@max_retries}" unless valid_max_retries?
    end
  end
end
