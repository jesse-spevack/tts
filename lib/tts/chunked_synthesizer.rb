# frozen_string_literal: true

require "concurrent"

class TTS
  # Handles concurrent synthesis of multiple text chunks.
  # Processes chunks in parallel using a thread pool and concatenates results.
  class ChunkedSynthesizer
    CONTENT_FILTER_ERROR = "sensitive or harmful content"

    # Initialize a new chunked synthesizer.
    #
    # @param api_client [TTS::APIClient] API client for making synthesis calls
    # @param config [TTS::Config] Configuration object
    # @param logger [Logger] Logger instance
    def initialize(api_client:, config:, logger:)
      @api_client = api_client
      @config = config
      @logger = logger
    end

    # Synthesizes multiple text chunks concurrently and concatenates the results.
    # Chunks are processed in parallel using a thread pool.
    # Chunks that trigger content filters are skipped with a warning.
    #
    # @param chunks [Array<String>] Array of text chunks to synthesize
    # @param voice [String] Voice name to use
    # @return [String] Concatenated binary MP3 audio data
    # @raise [Google::Cloud::Error] if any chunk fails (except content filter)
    def synthesize(chunks, voice)
      return "" if chunks.empty?

      log_synthesis_start(chunks)

      start_time = Time.now
      pool = Concurrent::FixedThreadPool.new(@config.thread_pool_size)
      promises = launch_chunk_promises(chunks: chunks, voice: voice, pool: pool)

      results = wait_for_completion(promises)
      audio_parts = extract_audio_parts(results)

      cleanup_pool(pool)
      log_synthesis_complete(chunks: chunks, audio_parts: audio_parts, start_time: start_time)

      audio_parts.join
    end

    private

    def log_synthesis_start(chunks)
      @logger.info "Text too long, splitting into #{chunks.length} chunks..."
      @logger.info "Processing with #{@config.thread_pool_size} concurrent threads (Chirp3 quota: 200/min)..."
      @logger.info "Chunk sizes: #{chunks.map(&:bytesize).join(', ')} bytes"
      @logger.info ""
    end

    def launch_chunk_promises(chunks:, voice:, pool:)
      skipped_chunks = Concurrent::Array.new
      promises = []
      total = chunks.length

      chunks.each_with_index do |chunk, i|
        promise = Concurrent::Promise.execute(executor: pool) do
          process_chunk(chunk: chunk, index: i, total: total, voice: voice, skipped_chunks: skipped_chunks)
        end
        promises << promise
      end

      @skipped_chunks = skipped_chunks
      promises
    end

    def process_chunk(chunk:, index:, total:, voice:, skipped_chunks:)
      chunk_num = index + 1
      @logger.info "Chunk #{chunk_num}/#{total}: Starting (#{chunk.bytesize} bytes)"

      chunk_start = Time.now
      audio = synthesize_chunk_with_error_handling(chunk: chunk, chunk_num: chunk_num, total: total, voice: voice,
                                                   skipped_chunks: skipped_chunks)

      log_chunk_completion(chunk_num: chunk_num, total: total, chunk_start: chunk_start) if audio

      [index, audio]
    end

    def synthesize_chunk_with_error_handling(chunk:, chunk_num:, total:, voice:, skipped_chunks:)
      @api_client.call_with_retry(text: chunk, voice: voice, max_retries: @config.max_retries)
    rescue StandardError => e
      handle_chunk_error(error: e, chunk_num: chunk_num, total: total, skipped_chunks: skipped_chunks)
      nil
    end

    def handle_chunk_error(error:, chunk_num:, total:, skipped_chunks:)
      # Convert error message to UTF-8 safely to prevent encoding errors when logging
      safe_message = error.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

      if safe_message.include?(CONTENT_FILTER_ERROR)
        @logger.warn "Chunk #{chunk_num}/#{total}: ⚠ SKIPPED - Content filter"
        skipped_chunks << chunk_num
      else
        @logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - #{safe_message}"
        raise
      end
    end

    def log_chunk_completion(chunk_num:, total:, chunk_start:)
      chunk_duration = Time.now - chunk_start
      @logger.info "Chunk #{chunk_num}/#{total}: ✓ Done in #{chunk_duration.round(2)}s"
    end

    def wait_for_completion(promises)
      @logger.info ""
      @logger.info "Waiting for all chunks to complete..."
      promises.map(&:value!) # Use value! to raise errors from failed promises
    end

    def extract_audio_parts(results)
      results
        .compact
        .sort_by { |idx, _| idx }
        .map { |_, audio| audio }
        .compact
    end

    def cleanup_pool(pool)
      pool.shutdown
      pool.wait_for_termination
    end

    def log_synthesis_complete(chunks:, audio_parts:, start_time:)
      total_duration = Time.now - start_time

      @logger.info ""
      log_skipped_chunks if @skipped_chunks.any?

      @logger.info "Concatenating #{audio_parts.length}/#{chunks.length} audio chunks..."
      @logger.info "Total processing time: #{total_duration.round(2)}s"
      @logger.info "Average time per chunk: #{(total_duration / chunks.length).round(2)}s"
    end

    def log_skipped_chunks
      skipped_list = @skipped_chunks.sort.join(", ")
      @logger.warn "⚠ Warning: Skipped #{@skipped_chunks.length} chunk(s) due to content filtering: #{skipped_list}"
    end
  end
end
