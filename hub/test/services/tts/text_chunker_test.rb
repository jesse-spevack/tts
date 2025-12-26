# frozen_string_literal: true

require "test_helper"

class Tts::TextChunkerTest < ActiveSupport::TestCase
  setup do
    @chunker = Tts::TextChunker.new
  end

  test "returns single chunk for short text" do
    text = "Hello world."
    chunks = @chunker.chunk(text, 100)

    assert_equal 1, chunks.length
    assert_equal "Hello world.", chunks[0]
  end

  test "splits text at sentence boundaries" do
    text = "First sentence. Second sentence. Third sentence."
    chunks = @chunker.chunk(text, 30)

    assert chunks.length > 1
    chunks.each do |chunk|
      assert chunk.bytesize <= 30, "Chunk exceeds limit: #{chunk.bytesize} bytes"
    end
  end

  test "splits long sentences at clause boundaries" do
    text = "This is a very long sentence with multiple clauses, separated by commas, that needs to be split."
    chunks = @chunker.chunk(text, 40)

    assert chunks.length > 1
    chunks.each do |chunk|
      assert chunk.bytesize <= 40, "Chunk exceeds limit: #{chunk.bytesize} bytes"
    end
  end

  test "splits at word boundaries when no punctuation" do
    text = "word " * 20
    chunks = @chunker.chunk(text.strip, 25)

    assert chunks.length > 1
    chunks.each do |chunk|
      assert chunk.bytesize <= 25, "Chunk exceeds limit: #{chunk.bytesize} bytes"
    end
  end

  test "handles text exactly at byte limit" do
    text = "x" * 100
    chunks = @chunker.chunk(text, 100)

    assert_equal 1, chunks.length
    assert_equal text, chunks[0]
  end

  test "handles empty text" do
    chunks = @chunker.chunk("", 100)
    assert_equal [""], chunks
  end

  test "preserves content integrity" do
    text = "First sentence. Second sentence. Third sentence."
    chunks = @chunker.chunk(text, 25)

    reassembled = chunks.join(" ")
    # All words should be present
    %w[First Second Third sentence].each do |word|
      assert reassembled.include?(word), "Missing word: #{word}"
    end
  end
end
