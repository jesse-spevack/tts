# frozen_string_literal: true

require_relative "tts/config"
require_relative "tts/api_client"
require_relative "tts/text_chunker"
require_relative "tts/chunked_synthesizer"

class SynthesizesAudio
  include StructuredLogging

  # Characters actually sent to Google on the most recent successful #call.
  # Populated on success; reset to nil if a call raises. Callers use this
  # to record a TtsUsage row with the billed count rather than
  # source_text.length (which diverges after wrapping, chunking, retries,
  # and content-filter skips).
  attr_reader :last_billed_characters

  def initialize(config: Tts::Config.new)
    @config = config
    @api_client = Tts::ApiClient.new(config: config)
    @text_chunker = Tts::TextChunker.new
    @chunked_synthesizer = Tts::ChunkedSynthesizer.new(api_client: @api_client, config: config)
    @last_billed_characters = nil
  end

  def call(text:, voice: nil)
    log_info "tts_generation_started"
    voice ||= @config.voice_name
    @last_billed_characters = nil

    chunks = @text_chunker.chunk(text, @config.byte_limit)

    if chunks.length == 1
      audio_content = @api_client.call(text: chunks[0], voice: voice)
      billed = chunks[0].length
    else
      audio_content = @chunked_synthesizer.synthesize(chunks, voice)
      billed = @chunked_synthesizer.billed_characters
    end

    @last_billed_characters = billed
    log_info "tts_generation_completed", audio_bytes: audio_content.bytesize, billed_characters: billed
    audio_content
  end
end
