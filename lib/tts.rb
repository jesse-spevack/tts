require 'google/cloud/text_to_speech'
require 'concurrent'
require 'logger'
require_relative 'tts/config'

class TTS
  GOOGLE_BYTE_LIMIT = 850  # Gemini TTS limit for text field

  def initialize(provider:, logger: Logger.new($stdout))
    @provider = provider
    @logger = logger

    case @provider
    when :google
      @client = Google::Cloud::TextToSpeech.text_to_speech do |config|
        config.timeout = 300  # 5 minutes - Gemini TTS can take this long
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

  def synthesize_google(text, voice)
    voice ||= "en-GB-Chirp3-HD-Enceladus"

    if text.bytesize > GOOGLE_BYTE_LIMIT
      return synthesize_google_chunked(text, voice)
    end

    @logger.info "Making API call (#{text.bytesize} bytes) with voice: #{voice}..."

    input = { text: text }
    voice_params = {
      language_code: "en-GB",
      name: voice
    }
    audio_config = {
      audio_encoding: "MP3",
      speaking_rate: 1.5,
      pitch: 0.0
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

  def synthesize_google_chunked(text, voice)
    chunks = chunk_text(text, GOOGLE_BYTE_LIMIT)

    @logger.info "Text too long, splitting into #{chunks.length} chunks..."
    @logger.info "Processing with 10 concurrent threads (Chirp3 quota: 200/min)..."
    @logger.info "Chunk sizes: #{chunks.map(&:bytesize).join(', ')} bytes"
    @logger.info ""

    start_time = Time.now
    pool = Concurrent::FixedThreadPool.new(10)
    promises = []
    skipped_chunks = Concurrent::Array.new  # Thread-safe array

    # Launch all chunks as concurrent promises
    chunks.each_with_index do |chunk, i|
      promise = Concurrent::Promise.execute(executor: pool) do
        chunk_preview = chunk[0..60].gsub(/\n/, ' ')
        @logger.info "Chunk #{i + 1}/#{chunks.length}: Starting (#{chunk.bytesize} bytes)"

        chunk_start = Time.now
        audio = nil

        begin
          audio = synthesize_google_with_retry(chunk, voice, max_retries: 3)
          chunk_duration = Time.now - chunk_start
          @logger.info "Chunk #{i + 1}/#{chunks.length}: ✓ Done in #{chunk_duration.round(2)}s"
        rescue => e
          if e.message.include?("sensitive or harmful content")
            @logger.warn "Chunk #{i + 1}/#{chunks.length}: ⚠ SKIPPED - Content filter"
            skipped_chunks << i + 1
          else
            @logger.error "Chunk #{i + 1}/#{chunks.length}: ✗ Failed - #{e.message}"
            raise
          end
        end

        [i, audio]  # Return index and audio (audio may be nil if skipped)
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
      .compact  # Remove nils from skipped chunks

    # Clean up thread pool
    pool.shutdown
    pool.wait_for_termination

    total_duration = Time.now - start_time

    @logger.info ""
    if skipped_chunks.any?
      @logger.warn "⚠ Warning: Skipped #{skipped_chunks.length} chunk(s) due to content filtering: #{skipped_chunks.sort.join(', ')}"
    end

    @logger.info "Concatenating #{audio_parts.length}/#{chunks.length} audio chunks..."
    @logger.info "Total processing time: #{total_duration.round(2)}s"
    @logger.info "Average time per chunk: #{(total_duration / chunks.length).round(2)}s"
    audio_parts.join
  end

  def synthesize_google_with_retry(chunk, voice, max_retries: 3)
    retries = 0

    begin
      synthesize_google(chunk, voice)
    rescue Google::Cloud::ResourceExhaustedError => e
      # Rate limit hit
      if retries < max_retries
        retries += 1
        wait_time = 2 ** retries
        @logger.warn "Rate limit hit, waiting #{wait_time}s (retry #{retries}/#{max_retries})"
        sleep(wait_time)
        retry
      else
        raise
      end
    rescue Google::Cloud::Error => e
      # Other transient Google Cloud errors
      if retries < max_retries && e.message.include?("Deadline Exceeded")
        retries += 1
        @logger.warn "Timeout, retrying (#{retries}/#{max_retries})"
        sleep(1)
        retry
      else
        raise
      end
    end
  end

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
