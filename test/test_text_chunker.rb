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

  # Regression test for: Long title without punctuation merges with following text
  # Bug: When split_at_words processes text without ending punctuation, the last
  # chunk doesn't get a period, causing it to merge with following text when
  # re-validated by APIClient, creating sentences > MAX_SAFE_SENTENCE_BYTES
  def test_long_header_without_punctuation_produces_valid_sentences
    max_sentence = 50
    chunker = TTS::TextChunker.new(max_sentence_bytes: max_sentence)

    # Simulate a markdown header converted to plain text (no ending punctuation)
    # followed by article content. This mirrors the actual failure:
    # "Real Purchasing Power Over Time Is Not Economic Welfare Over Time"
    long_title = "This Is A Very Long Article Title Without Any Ending Punctuation"
    following_text = "This is the first paragraph of the article content."
    text = "#{long_title}\n#{following_text}"

    chunks = chunker.chunk(text, 500)

    # After chunking, every chunk should have sentences <= max_sentence_bytes
    # This is what APIClient.validate_sentence_length! will check
    chunks.each do |chunk|
      sentences = chunk.split(/(?<=[.!?])\s+/)
      sentences.each do |sentence|
        assert sentence.bytesize <= max_sentence,
               "Sentence too long (#{sentence.bytesize} bytes, max #{max_sentence}): #{sentence[0..50]}..."
      end
    end
  end

  # More specific test matching the exact failure from production logs
  def test_realistic_episode_title_failure_case
    # Use the actual MAX_SAFE_SENTENCE_BYTES limit from APIClient
    max_sentence = TTS::APIClient::MAX_SAFE_SENTENCE_BYTES # 300
    chunker = TTS::TextChunker.new(max_sentence_bytes: max_sentence)

    # This mirrors the actual failing episode:
    # Title: "Real Purchasing Power Over Time Is Not Economic Welfare Over Time" (66 chars)
    # The error showed 396 bytes, meaning title + following text merged
    long_title = "Real Purchasing Power Over Time Is Not Economic Welfare Over Time"
    # Add enough following text to exceed 300 bytes when merged with title
    following_text = "A critique of using real purchasing power measures to assess economic welfare over time which fails to account for many important factors in human wellbeing."

    # Simulate how text_processor produces this - header becomes plain text without period
    text = "#{long_title}\n\n#{following_text}"

    chunks = chunker.chunk(text, 5000) # Large chunk limit so we test sentence splitting only

    # Verify all resulting sentences are within API limits
    chunks.each do |chunk|
      sentences = chunk.split(/(?<=[.!?])\s+/)
      sentences.each do |sentence|
        assert sentence.bytesize <= max_sentence,
               "Sentence too long (#{sentence.bytesize} bytes, max #{max_sentence}): #{sentence[0..50]}..."
      end
    end
  end

  # Regression test for production failure: 396 byte sentence starting with title
  # Production error: "Sentence too long (396 bytes, max 300): Real Purchasing Power..."
  # This test creates text that matches the exact failure scenario
  def test_production_failure_396_bytes
    max_sentence = TTS::APIClient::MAX_SAFE_SENTENCE_BYTES # 300
    chunker = TTS::TextChunker.new(max_sentence_bytes: max_sentence)

    # Create text where the first "sentence" (everything before first period) is ~396 bytes
    # Key: NO commas, semicolons, or colons - only word boundaries for splitting
    title = "Real Purchasing Power Over Time Is Not Economic Welfare Over Time"

    # Build content without any punctuation that would allow clause-level splitting
    # This forces split_at_words to handle it
    content_no_punct = "means that comparing real purchasing power across different time " \
                       "periods does not actually tell us anything meaningful about economic " \
                       "welfare across those same time periods because the basket of goods " \
                       "and services that people consume changes dramatically over time with " \
                       "new products appearing constantly and old products disappearing"

    # First period appears here - making total "sentence" ~396 bytes
    first_period = "This is where the first sentence ends."

    # Combine: title + newlines + content + first period = one long "sentence"
    text = "#{title}\n\n#{content_no_punct} #{first_period} More normal sentences follow. And another one."

    # Verify our test setup: first "sentence" should be > 300 bytes
    sentences = text.split(/(?<=[.!?])\s+/)
    first_sentence_bytes = sentences[0].bytesize
    assert first_sentence_bytes > 300,
           "Test setup error: first sentence should be > 300 bytes, got #{first_sentence_bytes}"

    # Now run the chunker
    chunks = chunker.chunk(text, 850) # Use production byte_limit

    # Verify all resulting sentences are within API limits
    # This is exactly what APIClient.validate_sentence_length! checks
    chunks.each_with_index do |chunk, chunk_idx|
      sentences_in_chunk = chunk.split(/(?<=[.!?])\s+/)
      sentences_in_chunk.each_with_index do |sentence, sent_idx|
        assert sentence.bytesize <= max_sentence,
               "Chunk #{chunk_idx}, Sentence #{sent_idx} too long " \
               "(#{sentence.bytesize} bytes, max #{max_sentence}): #{sentence[0..50]}..."
      end
    end
  end
end
