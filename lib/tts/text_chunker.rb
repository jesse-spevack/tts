# frozen_string_literal: true

class TTS
  # Splits text into chunks that fit within a byte limit.
  # Attempts to split at sentence boundaries first, then at punctuation marks if needed.
  class TextChunker
    def initialize(logger: nil)
      @logger = logger
    end

    # Splits text into chunks that fit within the byte limit.
    #
    # @param text [String] The text to split into chunks
    # @param max_bytes [Integer] Maximum byte size for each chunk
    # @return [Array<String>] Array of text chunks, each <= max_bytes
    def chunk(text, max_bytes)
      return [text] if text.bytesize <= max_bytes

      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current_chunk = ""

      sentences.each do |sentence|
        if sentence.bytesize > max_bytes
          # Sentence too long for a single chunk - split it
          unless current_chunk.empty?
            chunks << current_chunk.strip
            current_chunk = ""
          end
          chunks.concat(split_long_sentence(sentence, max_bytes))
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

    private

    # Split a long sentence into smaller parts at natural boundaries
    def split_long_sentence(sentence, max_bytes)
      # Try splitting at clause boundaries first (comma, semicolon, colon)
      parts = sentence.split(/(?<=[,;:])\s+/)

      result = []
      current_part = ""

      parts.each do |part|
        if part.bytesize > max_bytes
          # Part still too long - split at word boundaries
          unless current_part.empty?
            result << current_part
            current_part = ""
          end
          result.concat(split_at_words(part, max_bytes))
        else
          test_part = current_part.empty? ? part : "#{current_part} #{part}"
          if test_part.bytesize > max_bytes
            result << current_part unless current_part.empty?
            current_part = part
          else
            current_part = test_part
          end
        end
      end

      result << current_part unless current_part.empty?
      result
    end

    # Split text at word boundaries
    def split_at_words(text, max_bytes)
      words = text.split(/\s+/)
      chunks = []
      current_chunk = ""

      words.each do |word|
        if word.bytesize > max_bytes
          # Single word exceeds limit - just include it
          chunks << current_chunk unless current_chunk.empty?
          @logger&.warn "Single word exceeds max_bytes: #{word[0..20]}... (#{word.bytesize} bytes)"
          chunks << word
          current_chunk = ""
        else
          test_chunk = current_chunk.empty? ? word : "#{current_chunk} #{word}"
          if test_chunk.bytesize > max_bytes
            chunks << current_chunk unless current_chunk.empty?
            current_chunk = word
          else
            current_chunk = test_chunk
          end
        end
      end

      chunks << current_chunk unless current_chunk.empty?
      chunks
    end
  end
end
