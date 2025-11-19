# Fix TTS API Sentence Length Error Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix Google TTS API errors caused by sentences exceeding maximum length by implementing smart sentence splitting

**Architecture:** Enhance TextChunker to detect and split long sentences at natural breakpoints (periods, commas, etc.) before they exceed API limits

**Tech Stack:** Ruby, Google Cloud Text-to-Speech API, Minitest

---

## Task 1: Research TTS API sentence limits

**Files:**
- Create: `docs/investigations/tts-sentence-limits.md`

**Step 1: Review Google TTS API documentation**

Search for sentence length limits in:
- Google Cloud TTS documentation
- API error messages from logs

**Step 2: Test current limits**

Create test script `test/research/sentence_length_test.rb`:

```ruby
require "test_helper"
require "tts"

# Research script - not a formal test
# Run with: ruby test/research/sentence_length_test.rb

config = TTS::Config.new
logger = Logger.new($stdout)
client = TTS::APIClient.new(config: config, logger: logger)

# Test increasing sentence lengths
test_sentences = [
  "A" * 100 + ".",
  "B" * 200 + ".",
  "C" * 300 + ".",
  "D" * 400 + ".",
  "E" * 500 + ".",
]

test_sentences.each do |sentence|
  begin
    logger.info "Testing sentence of #{sentence.bytesize} bytes..."
    client.call(text: sentence, voice: config.voice)
    logger.info "✓ Success at #{sentence.bytesize} bytes"
  rescue => e
    logger.error "✗ Failed at #{sentence.bytesize} bytes: #{e.message}"
  end
end
```

Note: This requires API credentials. Document limits found from error messages instead.

**Step 3: Document findings**

Create `docs/investigations/tts-sentence-limits.md`:

```markdown
# Google TTS API Sentence Length Limits

## Error Messages
From production logs (2025-11-17):

```
This request contains sentences that are too long. Consider splitting up
long sentences with sentence ending punctuation e.g. periods. Sentence
starting with: "Five(" is too long.
```

```
Sentence starting with: "Take " is too long.
```

## Limits
- **Sentence limit**: Unknown exact byte/character count
- **Recommendation**: Split at sentence boundaries (periods, question marks, exclamation points)
- **Fallback**: Split at clause boundaries (commas, semicolons, colons)

## Chunks Affected
- Chunk 678/735: "Five("
- Chunk 724/735: "Take "

## Solution
Enhance TextChunker to:
1. Detect sentences > safe threshold (suggest 300 bytes)
2. Split at clause boundaries when sentence is too long
3. Add validation before API call

## References
- Error logs: hub/error-report-2025-11-17.md
- Google TTS docs: https://cloud.google.com/text-to-speech/quotas
```

**Step 4: Commit investigation**

```bash
git add docs/investigations/tts-sentence-limits.md
git commit -m "docs: document TTS API sentence length limits

Research from production errors on 2025-11-17"
```

---

## Task 2: Add sentence length validation

**Files:**
- Modify: `lib/tts/text_chunker.rb`
- Create: `test/test_sentence_validator.rb`

**Step 1: Write failing test for long sentence detection**

```ruby
# test/test_sentence_validator.rb
require "test_helper"
require "tts"

class TestSentenceValidator < Minitest::Test
  def test_detects_long_sentence
    chunker = TTS::TextChunker.new
    long_sentence = "A" * 400 + "."

    assert chunker.sentence_too_long?(long_sentence, max_bytes: 300)
  end

  def test_accepts_normal_sentence
    chunker = TTS::TextChunker.new
    normal_sentence = "This is a normal sentence."

    refute chunker.sentence_too_long?(normal_sentence, max_bytes: 300)
  end

  def test_splits_long_sentence_at_commas
    chunker = TTS::TextChunker.new
    long_sentence = "First clause" + (", and another clause" * 20) + "."

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
end
```

**Step 2: Run test to verify it fails**

```bash
ruby test/test_sentence_validator.rb
```

Expected: FAIL - methods not found

**Step 3: Implement sentence validation methods**

Modify `lib/tts/text_chunker.rb`:

```ruby
class TTS
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
  end
end
```

**Step 4: Run test to verify it passes**

```bash
ruby test/test_sentence_validator.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add lib/tts/text_chunker.rb test/test_sentence_validator.rb
git commit -m "feat: add sentence length validation to TextChunker

Adds methods to detect and split sentences that exceed safe byte limits
for Google TTS API"
```

---

## Task 3: Integrate sentence splitting into chunking algorithm

**Files:**
- Modify: `lib/tts/text_chunker.rb:19-33`
- Modify: `test/test_text_chunker.rb`

**Step 1: Add test for long sentence handling in chunk method**

```ruby
# Add to test/test_text_chunker.rb

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
```

**Step 2: Run test to verify it fails**

```bash
ruby test/test_text_chunker.rb
```

Expected: FAIL - long sentences not split

**Step 3: Update chunk method to use sentence splitting**

Modify `lib/tts/text_chunker.rb`:

```ruby
def chunk(text, max_bytes)
  return [text] if text.bytesize <= max_bytes

  chunks = []
  current_chunk = ""

  sentences = text.split(/(?<=[.!?])\s+/)

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
```

**Step 4: Run test to verify it passes**

```bash
ruby test/test_text_chunker.rb
```

Expected: PASS

**Step 5: Run all TTS tests**

```bash
ruby test/test_*.rb
```

Expected: All PASS

**Step 6: Commit**

```bash
git add lib/tts/text_chunker.rb test/test_text_chunker.rb
git commit -m "feat: split long sentences before chunking

Prevents TTS API errors by splitting sentences that exceed safe
byte limits. Splits at natural boundaries (commas, words).

Fixes: Chunk 678 and 724 TTS API errors"
```

---

## Task 4: Add API-level validation as safety net

**Files:**
- Modify: `lib/tts/api_client.rb`
- Create: `test/test_api_client_validation.rb`

**Step 1: Write test for sentence length validation**

```ruby
# test/test_api_client_validation.rb
require "test_helper"
require "tts"

class TestAPIClientValidation < Minitest::Test
  def test_raises_on_long_sentence_in_text
    config = TTS::Config.new
    logger = Logger.new(nil) # Silent logger

    client = TTS::APIClient.new(config: config, logger: logger, client: MockTTSClient.new)

    long_sentence = "A" * 400 + "."

    error = assert_raises(ArgumentError) do
      client.call(text: long_sentence, voice: config.voice)
    end

    assert_match /sentence too long/i, error.message
  end

  def test_accepts_normal_text
    config = TTS::Config.new
    logger = Logger.new(nil)
    mock_client = MockTTSClient.new

    client = TTS::APIClient.new(config: config, logger: logger, client: mock_client)

    assert_nothing_raised do
      client.call(text: "Normal sentence.", voice: config.voice)
    end
  end
end

class MockTTSClient
  def synthesize_speech(*)
    OpenStruct.new(audio_content: "mock audio data")
  end
end
```

**Step 2: Run test to verify it fails**

```bash
ruby test/test_api_client_validation.rb
```

Expected: FAIL - no validation

**Step 3: Add pre-flight validation to APIClient**

```ruby
# lib/tts/api_client.rb

# Add at top of class
MAX_SAFE_SENTENCE_BYTES = 300

def call(text:, voice:)
  # Validate sentence length before API call
  validate_sentence_length!(text)

  @logger.info "Making API call (#{text.bytesize} bytes) with voice: #{voice}..."

  response = @client.synthesize_speech(
    input: { text: text },
    voice: build_voice_params(voice),
    audio_config: build_audio_config
  )

  @logger.info "API call successful (#{response.audio_content.bytesize} bytes audio)"
  response.audio_content
rescue StandardError => e
  @logger.error "API call failed: #{e.message}"
  raise
end

private

def validate_sentence_length!(text)
  sentences = text.split(/(?<=[.!?])\s+/)

  sentences.each do |sentence|
    if sentence.bytesize > MAX_SAFE_SENTENCE_BYTES
      raise ArgumentError, "Sentence too long (#{sentence.bytesize} bytes, max #{MAX_SAFE_SENTENCE_BYTES}): #{sentence[0..50]}..."
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
ruby test/test_api_client_validation.rb
```

Expected: PASS

**Step 5: Test integration**

```bash
ruby test/test_*.rb
```

Expected: All tests PASS

**Step 6: Commit**

```bash
git add lib/tts/api_client.rb test/test_api_client_validation.rb
git commit -m "feat: add sentence length validation in API client

Safety net to catch any long sentences that slip through chunker.
Provides clear error message for debugging.

This prevents cryptic API errors and helps identify chunker bugs"
```

---

## Task 5: Add monitoring and metrics

**Files:**
- Modify: `lib/tts/chunked_synthesizer.rb`

**Step 1: Add sentence length logging**

```ruby
# In lib/tts/chunked_synthesizer.rb

def log_synthesis_start(chunks)
  @logger.info "Text too long, splitting into #{chunks.length} chunks..."
  @logger.info "Processing with #{@config.thread_pool_size} concurrent threads (Chirp3 quota: 200/min)..."
  @logger.info "Chunk sizes: #{chunks.map(&:bytesize).join(', ')} bytes"

  # Add sentence analysis
  sentence_lengths = chunks.flat_map { |chunk| chunk.split(/(?<=[.!?])\s+/).map(&:bytesize) }
  max_sentence = sentence_lengths.max
  avg_sentence = sentence_lengths.sum / sentence_lengths.length

  @logger.info "Sentence stats: max=#{max_sentence} bytes, avg=#{avg_sentence} bytes, count=#{sentence_lengths.length}"

  if max_sentence > 300
    @logger.warn "⚠ Warning: Found sentence > 300 bytes (#{max_sentence} bytes) - may trigger API error"
  end

  @logger.info ""
end
```

**Step 2: Manual test with long content**

Create test file with intentionally long sentences and process it.

**Step 3: Verify logging output**

Check that logs show sentence statistics and warnings.

**Step 4: Commit**

```bash
git add lib/tts/chunked_synthesizer.rb
git commit -m "feat: add sentence length monitoring to synthesizer

Logs sentence statistics to help identify potential API issues
before they occur"
```

---

## Verification

**Unit tests:**
```bash
cd /Users/jesse/code/tts
ruby test/test_*.rb
```

Expected: All tests PASS

**Integration test with real content:**

1. Find a document with long sentences
2. Process with updated chunker:
```bash
cd /Users/jesse/code/tts
ruby -Ilib -e '
require "tts"
config = TTS::Config.new
logger = Logger.new($stdout)
chunker = TTS::TextChunker.new

text = File.read("path/to/long-sentence-doc.md")
chunks = chunker.chunk(text, 800)

puts "Created #{chunks.length} chunks"
chunks.each_with_index do |chunk, i|
  sentences = chunk.split(/(?<=[.!?])\s+/)
  max_sentence = sentences.map(&:bytesize).max
  puts "Chunk #{i+1}: #{chunk.bytesize} bytes, max sentence: #{max_sentence} bytes"
end
'
```

Expected: No sentences > 300 bytes

**Monitor production:**

After deployment, check logs for:
- No more "sentence too long" errors
- Sentence stats look reasonable

**Deployment:**
```bash
# From generator directory
git push origin main
# Redeploy Cloud Run service
gcloud run deploy podcast-api --region us-west3 --source .
```
