# frozen_string_literal: true

require_relative "tts/config"
require_relative "tts/api_client"
require_relative "tts/text_chunker"
require_relative "tts/chunked_synthesizer"

module Tts
  # Text-to-Speech conversion using Google Cloud TTS API.
  class Synthesizer
    def initialize(config: Config.new)
      @config = config
      @api_client = ApiClient.new(config: config)
      @text_chunker = TextChunker.new
      @chunked_synthesizer = ChunkedSynthesizer.new(api_client: @api_client, config: config)
    end

    def synthesize(text, voice: nil)
      Rails.logger.info "[TTS] Generating audio..."
      voice ||= @config.voice_name

      chunks = @text_chunker.chunk(text, @config.byte_limit)

      audio_content = if chunks.length == 1
                        @api_client.call(text: chunks[0], voice: voice)
                      else
                        @chunked_synthesizer.synthesize(chunks, voice)
                      end

      Rails.logger.info "[TTS] Generated #{format_size(audio_content.bytesize)}"
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
end
