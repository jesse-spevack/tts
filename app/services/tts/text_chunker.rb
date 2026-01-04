# frozen_string_literal: true

module Tts
  # Splits text into chunks that fit within a byte limit.
  class TextChunker
    include StructuredLogging

    def initialize; end

    def chunk(text, max_bytes)
      return [ text ] if text.bytesize <= max_bytes

      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current_chunk = ""

      sentences.each do |sentence|
        if sentence.bytesize > max_bytes
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

    def split_long_sentence(sentence, max_bytes)
      parts = sentence.split(/(?<=[,;:])\s+/)
      result = []
      current_part = ""

      parts.each do |part|
        if part.bytesize > max_bytes
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

    def split_at_words(text, max_bytes)
      words = text.split(/\s+/)
      chunks = []
      current_chunk = ""

      words.each do |word|
        if word.bytesize > max_bytes
          chunks << current_chunk unless current_chunk.empty?
          log_warn "tts_word_exceeds_max_bytes", word_preview: word[0..20], bytes: word.bytesize
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
