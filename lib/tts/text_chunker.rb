# frozen_string_literal: true

class TTS
  # Splits text into chunks that fit within a byte limit.
  # Attempts to split at sentence boundaries first, then at punctuation marks if needed.
  # Preserves natural reading flow by keeping sentences together when possible.
  class TextChunker
    # Maximum bytes for a single sentence before splitting
    # Google TTS API rejects sentences that are too long
    DEFAULT_MAX_SENTENCE_BYTES = 300

    def initialize(max_sentence_bytes: DEFAULT_MAX_SENTENCE_BYTES)
      @max_sentence_bytes = max_sentence_bytes
    end

    # Check if a sentence exceeds the safe length
    def sentence_too_long?(sentence, max_bytes: @max_sentence_bytes)
      sentence.bytesize > max_bytes
    end

    # Split a long sentence into smaller parts at natural boundaries
    # Tries: periods, commas/semicolons/colons, then word boundaries
    def split_long_sentence(sentence, max_bytes: @max_sentence_bytes)
      return [sentence] unless sentence_too_long?(sentence, max_bytes: max_bytes)

      # Try splitting at clause boundaries first (comma, semicolon, colon)
      parts = sentence.split(/(?<=[,;:])\s+/)

      # If parts are still too long, split at word boundaries
      result = []
      parts.each do |part|
        if part.bytesize > max_bytes
          result.concat(split_at_words(part, max_bytes))
        else
          result << part
        end
      end

      result
    end

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

    # Split text at word boundaries
    def split_at_words(text, max_bytes)
      words = text.split(/\s+/)
      chunks = []
      current_chunk = ""

      words.each do |word|
        test_chunk = current_chunk.empty? ? word : "#{current_chunk} #{word}"

        if test_chunk.bytesize > max_bytes
          chunks << current_chunk unless current_chunk.empty?
          current_chunk = word
        else
          current_chunk = test_chunk
        end
      end

      chunks << current_chunk unless current_chunk.empty?
      chunks
    end

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
