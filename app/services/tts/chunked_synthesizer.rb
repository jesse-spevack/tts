# frozen_string_literal: true

require "concurrent"

module Tts
  # Handles concurrent synthesis of multiple text chunks.
  class ChunkedSynthesizer
    include StructuredLogging

    def initialize(api_client:, config:)
      @api_client = api_client
      @config = config
    end

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
      log_info "tts_chunked_synthesis_started",
               chunk_count: chunks.length,
               thread_pool_size: @config.thread_pool_size,
               chunk_sizes: chunks.map(&:bytesize).join(",")
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
      log_info "tts_chunk_started", chunk: chunk_num, total: total, bytes: chunk.bytesize

      chunk_start = Time.now
      audio = synthesize_chunk_with_error_handling(chunk: chunk, chunk_num: chunk_num, total: total, voice: voice,
                                                   skipped_chunks: skipped_chunks)

      log_chunk_completion(chunk_num: chunk_num, total: total, chunk_start: chunk_start) if audio

      [ index, audio ]
    end

    def synthesize_chunk_with_error_handling(chunk:, chunk_num:, total:, voice:, skipped_chunks:)
      @api_client.call(text: chunk, voice: voice)
    rescue StandardError => e
      handle_chunk_error(error: e, chunk_num: chunk_num, total: total, skipped_chunks: skipped_chunks)
      nil
    end

    def handle_chunk_error(error:, chunk_num:, total:, skipped_chunks:)
      safe_message = error.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

      if safe_message.include?(Tts::Constants::CONTENT_FILTER_ERROR)
        log_warn "tts_chunk_skipped", chunk: chunk_num, total: total, reason: "content_filter"
        skipped_chunks << chunk_num
      else
        log_error "tts_chunk_failed", chunk: chunk_num, total: total, error: safe_message
        raise
      end
    end

    def log_chunk_completion(chunk_num:, total:, chunk_start:)
      chunk_duration = Time.now - chunk_start
      log_info "tts_chunk_completed", chunk: chunk_num, total: total, duration_seconds: chunk_duration.round(2)
    end

    def wait_for_completion(promises)
      log_info "tts_waiting_for_chunks"
      promises.map(&:value!)
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

      if @skipped_chunks.any?
        log_warn "tts_chunks_skipped",
                 skipped_count: @skipped_chunks.length,
                 skipped_chunks: @skipped_chunks.sort.join(",")
      end

      log_info "tts_chunked_synthesis_completed",
               chunks_processed: audio_parts.length,
               chunks_total: chunks.length,
               duration_seconds: total_duration.round(2)
    end
  end
end
