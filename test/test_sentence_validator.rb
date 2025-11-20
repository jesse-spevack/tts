# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/tts/text_chunker"

class TestSentenceValidator < Minitest::Test
  def test_detects_long_sentence
    chunker = TTS::TextChunker.new
    long_sentence = "#{'A' * 400}."

    assert chunker.sentence_too_long?(long_sentence, max_bytes: 300)
  end

  def test_accepts_normal_sentence
    chunker = TTS::TextChunker.new
    normal_sentence = "This is a normal sentence."

    refute chunker.sentence_too_long?(normal_sentence, max_bytes: 300)
  end

  def test_splits_long_sentence_at_commas
    chunker = TTS::TextChunker.new
    long_sentence = "First clause#{', and another clause' * 20}."

    parts = chunker.split_long_sentence(long_sentence, max_bytes: 100)

    assert parts.length > 1
    parts.each do |part|
      assert part.bytesize <= 100, "Part exceeds 100 bytes: #{part.bytesize}"
    end
  end

  def test_splits_at_word_boundaries_when_no_punctuation
    chunker = TTS::TextChunker.new
    long_sentence = "word " * 100

    parts = chunker.split_long_sentence(long_sentence, max_bytes: 50)

    assert parts.length > 1
    parts.each do |part|
      assert part.bytesize <= 50, "Part exceeds 50 bytes: #{part.bytesize}"
    end
  end

  def test_handles_single_word_exceeding_max_bytes
    logger = Minitest::Mock.new
    logger.expect :warn, nil, [String]

    chunker = TTS::TextChunker.new(logger: logger)
    # Create a single very long word (350 bytes, which exceeds the 300 byte default)
    long_word = "A" * 350

    parts = chunker.split_long_sentence(long_word, max_bytes: 300)

    # Should return the word as-is even though it exceeds limit
    assert_equal 1, parts.length
    assert_equal long_word, parts[0]
    logger.verify
  end
end
