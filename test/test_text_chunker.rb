# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/tts/text_chunker"

class TestTextChunker < Minitest::Test
  def setup
    @chunker = TTS::TextChunker.new
  end

  def test_short_text_returns_single_chunk
    text = "This is a short text."
    chunks = @chunker.chunk(text, 1000)

    assert_equal 1, chunks.length
    assert_equal text, chunks[0]
  end

  def test_splits_at_sentence_boundaries
    text = "First sentence. Second sentence. Third sentence."
    chunks = @chunker.chunk(text, 30)

    assert chunks.length > 1
    chunks.each do |chunk|
      assert chunk.bytesize <= 30
    end
  end

  def test_splits_long_sentences_at_punctuation
    text = "This is a very long sentence with commas, semicolons; and colons: to split on."
    chunks = @chunker.chunk(text, 30)

    assert chunks.length > 1
  end

  def test_preserves_all_text_content
    text = "First sentence. Second sentence. Third sentence. Fourth sentence."
    chunks = @chunker.chunk(text, 25)

    reconstructed = chunks.join(" ")
    # Text should be preserved (allowing for whitespace normalization)
    assert_equal text.split.join(" "), reconstructed.split.join(" ")
  end

  def test_handles_text_exactly_at_limit
    text = "a" * 100
    chunks = @chunker.chunk(text, 100)

    assert_equal 1, chunks.length
    assert_equal text, chunks[0]
  end

  def test_handles_single_word_exceeding_limit
    # When a single word/part exceeds limit, it should still be included
    text = "Short. #{'a' * 150}. Short."
    chunks = @chunker.chunk(text, 100)

    # Should have the long word in its own chunk
    assert(chunks.any? { |chunk| chunk.bytesize > 100 })
  end

  def test_no_empty_chunks
    text = "First. Second. Third. Fourth. Fifth."
    chunks = @chunker.chunk(text, 10)

    chunks.each do |chunk|
      refute_empty chunk.strip
    end
  end

  def test_splits_multiple_sentences
    sentences = (1..10).map { |i| "Sentence number #{i}." }.join(" ")
    chunks = @chunker.chunk(sentences, 50)

    assert chunks.length > 1
    chunks.each do |chunk|
      assert chunk.bytesize <= 50 || chunk.split(/[.!?]/).length == 1
    end
  end

  def test_splits_long_sentences_within_chunks
    chunker = TTS::TextChunker.new(max_sentence_bytes: 50)

    # Create text with one very long sentence
    long_sentence = "word " * 30 + "."
    text = "Short sentence. #{long_sentence} Another short sentence."

    chunks = chunker.chunk(text, 200)

    # Verify no chunk contains a sentence > 50 bytes
    chunks.each do |chunk|
      sentences = chunk.split(/(?<=[.!?])\s+/)
      sentences.each do |sentence|
        assert sentence.bytesize <= 50, "Sentence too long: #{sentence.bytesize} bytes"
      end
    end
  end

  def test_handles_parenthetical_long_content
    chunker = TTS::TextChunker.new(max_sentence_bytes: 100)

    # Simulate "Five(" pattern from logs
    text = "Five(a very long parenthetical expression that goes on and on and on and on and on and on and on and on) is a number."

    chunks = chunker.chunk(text, 200)

    # Should not raise error, should split appropriately
    assert chunks.length > 0
    chunks.each do |chunk|
      assert chunk.bytesize <= 200
    end
  end
end
