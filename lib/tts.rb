# frozen_string_literal: true

require "logger"
require_relative "tts/config"
require_relative "tts/api_client"
require_relative "tts/text_chunker"
require_relative "tts/chunked_synthesizer"

# Text-to-Speech conversion library using Google Cloud Text-to-Speech API.
#
# Provides high-level interface for converting text to speech audio with features including:
# - Automatic text chunking for large inputs that exceed Google's byte limits
# - Concurrent processing of chunks using thread pools for performance
# - Automatic retry logic with exponential backoff for rate limits and transient errors
# - Content filtering with graceful degradation (skips filtered chunks)
# - Configurable voice, speaking rate, pitch, and other TTS parameters
# - Structured logging with customizable logger
#
# @example Basic usage with default configuration
#   tts = TTS.new
#   audio_data = tts.synthesize("Hello, world!")
#   File.write("output.mp3", audio_data)
#
# @example Custom configuration
#   config = TTS::Config.new(
#     speaking_rate: 2.0,
#     thread_pool_size: 5,
#     byte_limit: 1000
#   )
#   tts = TTS.new(config: config)
#   audio_data = tts.synthesize("Long text...", voice: "en-US-Chirp3-HD-Galahad")
#
# @example Custom logger
#   logger = Logger.new('tts.log')
#   logger.level = Logger::WARN
#   tts = TTS.new(logger: logger)
#
# @example Silent mode (no logging output)
#   tts = TTS.new(logger: Logger.new(File::NULL))
#
class TTS
  # Initialize a new TTS instance.
  #
  # @param config [TTS::Config] Configuration object (defaults to TTS::Config.new)
  # @param logger [Logger] Logger instance (defaults to Logger.new($stdout))
  def initialize(config: Config.new, logger: Logger.new($stdout))
    @config = config
    @logger = logger

    @api_client = TTS::APIClient.new(config, logger)
    @text_chunker = TTS::TextChunker.new
    @chunked_synthesizer = TTS::ChunkedSynthesizer.new(@api_client, config, logger)
  end

  # Converts text to speech and returns audio content as binary data.
  # Automatically chunks text if it exceeds byte limit.
  #
  # @param text [String] The text to convert to speech
  # @param voice [String, nil] Voice name (optional, uses config default if not provided)
  # @return [String] Binary MP3 audio data
  # @raise [Google::Cloud::Error] if API call fails
  def synthesize(text, voice: nil)
    puts "\n[2/4] Generating audio..."
    voice ||= @config.voice_name

    chunks = @text_chunker.chunk(text, @config.byte_limit)

    audio_content = if chunks.length == 1
                      @api_client.call(text: chunks[0], voice: voice)
                    else
                      @chunked_synthesizer.synthesize(chunks, voice)
                    end

    puts "✓ Generated #{format_size(audio_content.bytesize)}"
    audio_content
  end

  private

  def format_size(bytes)
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end
end
