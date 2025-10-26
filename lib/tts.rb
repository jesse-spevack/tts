# frozen_string_literal: true

require "google/cloud/text_to_speech"
require "concurrent"
require "logger"
require_relative "tts/config"

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
#   tts = TTS.new(provider: :google)
#   audio_data = tts.synthesize("Hello, world!")
#   File.write("output.mp3", audio_data)
#
# @example Custom configuration
#   config = TTS::Config.new(
#     speaking_rate: 2.0,
#     thread_pool_size: 5,
#     byte_limit: 1000
#   )
#   tts = TTS.new(provider: :google, config: config)
#   audio_data = tts.synthesize("Long text...", voice: "en-US-Chirp3-HD-Galahad")
#
# @example Custom logger
#   logger = Logger.new('tts.log')
#   logger.level = Logger::WARN
#   tts = TTS.new(provider: :google, logger: logger)
#
# @example Silent mode (no logging output)
#   tts = TTS.new(provider: :google, logger: Logger.new(File::NULL))
#
class TTS
  CONTENT_FILTER_ERROR = "sensitive or harmful content"
  DEADLINE_EXCEEDED_ERROR = "Deadline Exceeded"

  # Initialize a new TTS instance.
  #
  # @param provider [Symbol] The TTS provider to use (currently only :google is supported)
  # @param config [TTS::Config] Configuration object (defaults to TTS::Config.new)
  # @param logger [Logger] Logger instance (defaults to Logger.new($stdout))
  # @raise [NotImplementedError] if provider is not :google
  # @raise [ArgumentError] if provider is unknown
  def initialize(provider:, config: Config.new, logger: Logger.new($stdout))
    @provider = provider
    @config = config
    @logger = logger

    case @provider
    when :google
      @client = Google::Cloud::TextToSpeech.text_to_speech do |client_config|
        client_config.timeout = @config.timeout
      end
    when :open_ai, :eleven_labs
      raise NotImplementedError, "#{@provider} provider not yet implemented"
    else
      raise ArgumentError, "Unknown provider: #{@provider}. Supported: :google, :open_ai, :eleven_labs"
    end
  end

  # Converts text to speech and returns audio content as binary data
  # @param text [String] The text to convert to speech
  # @param voice [String] Voice name (optional, uses default if not provided)
  # @return [String] Binary audio data (MP3 format)
  def synthesize(text, voice: nil)
    case @provider
    when :google
      synthesize_google(text, voice)
    else
      raise NotImplementedError, "#{@provider} provider not yet implemented"
    end
  end

  private

  # Synthesizes text using Google Cloud TTS API.
  # Automatically routes to chunked synthesis if text exceeds byte limit.
  #
  # @param text [String] The text to convert to speech
  # @param voice [String, nil] Voice name (uses config default if nil)
  # @return [String] Binary MP3 audio data
  # @raise [Google::Cloud::Error] if API call fails
  def synthesize_google(text, voice)
    voice ||= @config.voice_name

    return synthesize_google_chunked(text, voice) if text.bytesize > @config.byte_limit

    @logger.info "Making API call (#{text.bytesize} bytes) with voice: #{voice}..."

    input = {text: text}
    voice_params = {
      language_code: @config.language_code,
      name: voice
    }
    audio_config = {
      audio_encoding: @config.audio_encoding,
      speaking_rate: @config.speaking_rate,
      pitch: @config.pitch
    }

    response = @client.synthesize_speech(
      input: input,
      voice: voice_params,
      audio_config: audio_config
    )

    @logger.info "API call successful (#{response.audio_content.bytesize} bytes audio)"
    response.audio_content
  rescue => e
    @logger.error "API call failed: #{e.message}"
    raise
  end

  # Synthesizes long text by splitting into chunks and processing concurrently.
  # Chunks are processed in parallel using a thread pool and concatenated together.
  # Chunks that trigger content filters are skipped with a warning.
  #
  # @param text [String] The text to convert (must exceed byte_limit)
  # @param voice [String] Voice name to use
  # @return [String] Concatenated binary MP3 audio data
  # @raise [Google::Cloud::Error] if any chunk fails (except content filter)
  def synthesize_google_chunked(text, voice)
    chunks = chunk_text(text, @config.byte_limit)

    @logger.info "Text too long, splitting into #{chunks.length} chunks..."
    @logger.info "Processing with #{@config.thread_pool_size} concurrent threads (Chirp3 quota: 200/min)..."
    @logger.info "Chunk sizes: #{chunks.map(&:bytesize).join(", ")} bytes"
    @logger.info ""

    start_time = Time.now
    pool = Concurrent::FixedThreadPool.new(@config.thread_pool_size)
    promises = []
    skipped_chunks = Concurrent::Array.new # Thread-safe array

    # Launch all chunks as concurrent promises
    chunks.each_with_index do |chunk, i|
      promise = Concurrent::Promise.execute(executor: pool) do
        chunk[0..60].tr("\n", " ")
        @logger.info "Chunk #{i + 1}/#{chunks.length}: Starting (#{chunk.bytesize} bytes)"

        chunk_start = Time.now
        audio = nil

        begin
          audio = synthesize_google_with_retry(chunk, voice, max_retries: @config.max_retries)
          chunk_duration = Time.now - chunk_start
          @logger.info "Chunk #{i + 1}/#{chunks.length}: ✓ Done in #{chunk_duration.round(2)}s"
        rescue => e
          if e.message.include?(CONTENT_FILTER_ERROR)
            @logger.warn "Chunk #{i + 1}/#{chunks.length}: ⚠ SKIPPED - Content filter"
            skipped_chunks << i + 1
          else
            @logger.error "Chunk #{i + 1}/#{chunks.length}: ✗ Failed - #{e.message}"
            raise
          end
        end

        [i, audio] # Return index and audio (audio may be nil if skipped)
      end

      promises << promise
    end

    # Wait for all promises to complete
    @logger.info ""
    @logger.info "Waiting for all chunks to complete..."
    results = promises.map(&:value)

    # Sort by index and extract non-nil audio
    # Filter out nil results (from failed promises) before sorting
    audio_parts = results
      .compact
      .sort_by { |idx, _| idx }
      .map { |_, audio| audio }
      .compact # Remove nils from skipped chunks

    # Clean up thread pool
    pool.shutdown
    pool.wait_for_termination

    total_duration = Time.now - start_time

    @logger.info ""
    if skipped_chunks.any?
      @logger.warn "⚠ Warning: Skipped #{skipped_chunks.length} chunk(s) due to content filtering: #{skipped_chunks.sort.join(", ")}"
    end

    @logger.info "Concatenating #{audio_parts.length}/#{chunks.length} audio chunks..."
    @logger.info "Total processing time: #{total_duration.round(2)}s"
    @logger.info "Average time per chunk: #{(total_duration / chunks.length).round(2)}s"
    audio_parts.join
  end

  # Synthesizes a single chunk with automatic retry logic.
  # Retries on rate limits (ResourceExhaustedError) and timeouts (Deadline Exceeded).
  # Uses exponential backoff for rate limits.
  #
  # @param chunk [String] The text chunk to synthesize
  # @param voice [String] Voice name to use
  # @param max_retries [Integer] Maximum number of retry attempts
  # @return [String] Binary MP3 audio data
  # @raise [Google::Cloud::ResourceExhaustedError] if max retries exceeded on rate limit
  # @raise [Google::Cloud::Error] if max retries exceeded on timeout or other errors
  def synthesize_google_with_retry(chunk, voice, max_retries:)
    retries = 0

    begin
      synthesize_google(chunk, voice)
    rescue Google::Cloud::ResourceExhaustedError => e
      # Rate limit hit
      raise unless retries < max_retries

      retries += 1
      wait_time = 2**retries
      @logger.warn "Rate limit hit, waiting #{wait_time}s (retry #{retries}/#{max_retries})"
      sleep(wait_time)
      retry
    rescue Google::Cloud::Error => e
      # Other transient Google Cloud errors
      raise unless retries < max_retries && e.message.include?(DEADLINE_EXCEEDED_ERROR)

      retries += 1
      @logger.warn "Timeout, retrying (#{retries}/#{max_retries})"
      sleep(1)
      retry
    end
  end

  # Splits text into chunks that fit within the byte limit.
  # Attempts to split at sentence boundaries first, then at punctuation marks if needed.
  # Preserves natural reading flow by keeping sentences together when possible.
  #
  # @param text [String] The text to split into chunks
  # @param max_bytes [Integer] Maximum byte size for each chunk
  # @return [Array<String>] Array of text chunks, each <= max_bytes
  def chunk_text(text, max_bytes)
    return [text] if text.bytesize <= max_bytes

    chunks = []
    current_chunk = ""

    sentences = text.split(/(?<=[.!?])\s+/)

    sentences.each do |sentence|
      if sentence.bytesize > max_bytes
        parts = sentence.split(/(?<=[,;:])\s+/)
        parts.each do |part|
          test_chunk = current_chunk.empty? ? part : "#{current_chunk} #{part}"
          if test_chunk.bytesize > max_bytes
            chunks << current_chunk.strip unless current_chunk.empty?
            current_chunk = part
          else
            current_chunk = test_chunk
          end
        end
      else
        test_chunk = current_chunk.empty? ? sentence : "#{current_chunk} #{sentence}"
        if test_chunk.bytesize > max_bytes
          chunks << current_chunk.strip unless current_chunk.empty?
          current_chunk = sentence
        else
          current_chunk = test_chunk
        end
      end
    end

    chunks << current_chunk.strip unless current_chunk.empty?
    chunks
  end
end
