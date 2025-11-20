# frozen_string_literal: true

class TTS
  # Splits text into chunks that fit within a byte limit.
  # Attempts to split at sentence boundaries first, then at punctuation marks if needed.
  # Preserves natural reading flow by keeping sentences together when possible.
  class TextChunker
    # Maximum bytes for a single sentence before splitting
    # Google TTS API rejects sentences that are too long
    DEFAULT_MAX_SENTENCE_BYTES = 300

    def initialize(max_sentence_bytes: DEFAULT_MAX_SENTENCE_BYTES, logger: nil)
      @max_sentence_bytes = max_sentence_bytes
      @logger = logger
    end

    # Check if a sentence exceeds the safe length
    def sentence_too_long?(sentence, max_bytes: @max_sentence_bytes)
      sentence.bytesize > max_bytes
    end

    # Split a long sentence into smaller parts at natural boundaries
    # Tries: commas/semicolons/colons, then word boundaries
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
      # First check if any sentences are too long, even if text fits in one chunk
      sentences = text.split(/(?<=[.!?])\s+/)
      has_long_sentences = sentences.any? { |s| sentence_too_long?(s, max_bytes: @max_sentence_bytes) }

      # If text fits in one chunk AND has no long sentences, return as-is
      return [text] if text.bytesize <= max_bytes && !has_long_sentences

      chunks = []
      current_chunk = ""

      sentences.each do |sentence|
        # Check if sentence itself is too long
        if sentence_too_long?(sentence, max_bytes: @max_sentence_bytes)
          # Split the long sentence first
          sentence_parts = split_long_sentence(sentence, max_bytes: @max_sentence_bytes)

          sentence_parts.each do |part|
            current_chunk = add_sentence_to_chunk(
              sentence: part,
              current_chunk: current_chunk,
              max_bytes: max_bytes,
              chunks: chunks
            )
          end
        elsif sentence.bytesize > max_bytes
          # Sentence fits API limits but not in chunk
          process_long_sentence(
            sentence: sentence,
            max_bytes: max_bytes,
            chunks: chunks,
            current_chunk: current_chunk
          )
          current_chunk = chunks.pop || ""
        else
          current_chunk = add_sentence_to_chunk(
            sentence: sentence,
            current_chunk: current_chunk,
            max_bytes: max_bytes,
            chunks: chunks
          )
        end
      end

      chunks << current_chunk.strip unless current_chunk.empty?
      chunks
    end

    private

    # Split text at word boundaries
    # Adds period to split points to maintain sentence boundaries
    def split_at_words(text, max_bytes)
      # Check if the text ends with sentence-ending punctuation
      has_ending_punctuation = text =~ /[.!?]\s*$/

      # Remove trailing punctuation for processing, we'll add it back at the end
      text_to_split = text.sub(/[.!?]\s*$/, "")

      words = text_to_split.split(/\s+/)
      chunks = []
      current_chunk = ""

      words.each do |word|
        test_chunk = current_chunk.empty? ? word : "#{current_chunk} #{word}"

        if test_chunk.bytesize > max_bytes
          # Add period to create sentence boundary, but only if we're not adding to the last chunk
          chunks << current_chunk unless current_chunk.empty?
          # Handle case where single word exceeds max_bytes
          if word.bytesize > max_bytes
            @logger&.warn "Single word exceeds max_bytes: #{word[0..20]}... (#{word.bytesize} bytes)"
            chunks << word
            current_chunk = ""
          else
            current_chunk = word
          end
        else
          current_chunk = test_chunk
        end
      end

      chunks << current_chunk unless current_chunk.empty?

      # Add periods to all parts except the last to maintain sentence boundaries
      # The last part gets the original ending punctuation
      chunks.map.with_index do |chunk, i|
        if i == chunks.length - 1 && has_ending_punctuation
          "#{chunk}."
        elsif i < chunks.length - 1
          "#{chunk}."
        else
          chunk
        end
      end
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
