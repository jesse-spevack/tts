# frozen_string_literal: true

class TTS
  # Splits text into chunks that fit within a byte limit.
  # Attempts to split at sentence boundaries first, then at punctuation marks if needed.
  # Preserves natural reading flow by keeping sentences together when possible.
  class TextChunker
    # Splits text into chunks that fit within the byte limit.
    #
    # @param text [String] The text to split into chunks
    # @param max_bytes [Integer] Maximum byte size for each chunk
    # @return [Array<String>] Array of text chunks, each <= max_bytes
    def chunk(text, max_bytes)
      return [text] if text.bytesize <= max_bytes

      chunks = []
      current_chunk = ""

      sentences = text.split(/(?<=[.!?])\s+/)

      sentences.each do |sentence|
        if sentence.bytesize > max_bytes
          process_long_sentence(sentence: sentence, max_bytes: max_bytes, chunks: chunks, current_chunk: current_chunk)
          current_chunk = chunks.pop || ""
        else
          current_chunk = add_sentence_to_chunk(sentence: sentence, current_chunk: current_chunk, max_bytes: max_bytes,
                                                chunks: chunks)
        end
      end

      chunks << current_chunk.strip unless current_chunk.empty?
      chunks
    end

    private

    def process_long_sentence(sentence:, max_bytes:, chunks:, current_chunk:)
      parts = sentence.split(/(?<=[,;:])\s+/)
      parts.each do |part|
        current_chunk = add_part_to_chunk(part: part, current_chunk: current_chunk, max_bytes: max_bytes,
                                          chunks: chunks)
      end
      chunks << current_chunk
    end

    def add_sentence_to_chunk(sentence:, current_chunk:, max_bytes:, chunks:)
      test_chunk = build_test_chunk(current_chunk, sentence)
      if test_chunk.bytesize > max_bytes
        chunks << current_chunk.strip unless current_chunk.empty?
        sentence
      else
        test_chunk
      end
    end

    def add_part_to_chunk(part:, current_chunk:, max_bytes:, chunks:)
      test_chunk = build_test_chunk(current_chunk, part)
      if test_chunk.bytesize > max_bytes
        chunks << current_chunk.strip unless current_chunk.empty?
        part
      else
        test_chunk
      end
    end

    def build_test_chunk(current_chunk, new_text)
      current_chunk.empty? ? new_text : "#{current_chunk} #{new_text}"
    end
  end
end
