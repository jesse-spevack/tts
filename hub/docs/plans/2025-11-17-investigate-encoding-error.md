# Investigate and Fix Episode Encoding Error Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Investigate and fix "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)" error affecting episodes 15 and 18

**Architecture:** Systematic investigation to identify where binary/UTF-8 mixing occurs, then implement proper encoding handling

**Tech Stack:** Ruby on Rails 8, Google Cloud Storage, character encoding handling

---

## Task 1: Investigate Episode 15 and 18 data

**Files:**
- Investigation only (no file changes)

**Step 1: Check episode records in database**

Run Rails console:
```bash
rails console
```

Execute:
```ruby
episode_15 = Episode.find(15)
puts "Episode 15:"
puts "  Title: #{episode_15.title}"
puts "  Status: #{episode_15.status}"
puts "  Error: #{episode_15.error_message}"
puts "  Created: #{episode_15.created_at}"
puts ""

episode_18 = Episode.find(18)
puts "Episode 18:"
puts "  Title: #{episode_18.title}"
puts "  Status: #{episode_18.status}"
puts "  Error: #{episode_18.error_message}"
puts "  Created: #{episode_18.created_at}"
```

Expected: See episode details and error messages

**Step 2: Check if episodes have staging files**

Continue in Rails console:
```ruby
# Try to locate staging files for these episodes
bucket_name = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
podcast_id = episode_15.podcast.podcast_id

puts "Looking for staging files:"
puts "  Podcast ID: #{podcast_id}"
puts "  Bucket: #{bucket_name}"
```

**Step 3: Download staging files to inspect**

Using gcloud CLI:
```bash
# List staging files
gsutil ls gs://verynormal-tts-podcast/staging/

# Look for episode 15 and 18 files
gsutil ls gs://verynormal-tts-podcast/staging/ | grep -E "(15-|18-)"

# Download files for inspection
gsutil cp gs://verynormal-tts-podcast/staging/15-*.md /tmp/episode-15.md
gsutil cp gs://verynormal-tts-podcast/staging/18-*.md /tmp/episode-18.md
```

Expected: Downloaded markdown files

**Step 4: Inspect file encodings**

```bash
# Check file encoding
file /tmp/episode-15.md
file /tmp/episode-18.md

# Check for binary content
hexdump -C /tmp/episode-15.md | head -20
hexdump -C /tmp/episode-18.md | head -20

# Try to read as UTF-8
cat /tmp/episode-15.md
cat /tmp/episode-18.md
```

Expected: Identify if files contain binary data or encoding issues

**Step 5: Document findings**

Create investigation notes in `docs/investigations/encoding-error-2025-11-17.md`:

```markdown
# Encoding Error Investigation - Episodes 15 & 18

## Date
2025-11-17

## Episodes Affected
- Episode 15: [title]
- Episode 18: [title]

## Error Message
```
incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)
```

## Findings

### File Inspection
- File encoding: [result from `file` command]
- Contains binary: [yes/no]
- Special characters found: [list]

### Hypothesis
[Based on findings, state hypothesis about cause]

### Next Steps
[What to investigate/fix next]
```

**Step 6: Commit investigation notes**

```bash
git add docs/investigations/encoding-error-2025-11-17.md
git commit -m "docs: investigation notes for encoding error

Episodes 15 and 18 experiencing UTF-8/BINARY encoding issues"
```

---

## Task 2: Trace error in generator codebase

**Files:**
- Investigation in generator repository

**Step 1: Check generator logs for episodes 15 and 18**

```bash
# Search GCP logs for these episodes
gcloud run services logs read podcast-api --region us-west3 --limit 2000 --freshness=72h | grep -E "episode.*1[58]"
```

Expected: Find processing logs for these episodes

**Step 2: Review text processing pipeline**

Check where encoding conversion might be needed:

Files to review:
- Generator's markdown processor
- Text chunker
- Any string concatenation with file content

Look for:
```ruby
# Dangerous patterns:
file_content + some_string  # Binary + UTF-8
"#{binary_data}..."         # String interpolation with binary
```

**Step 3: Identify the exact location**

Search for string operations on file content:

```bash
cd /path/to/generator
grep -rn "\.read" --include="*.rb" lib/
grep -rn "encode\|force_encoding" --include="*.rb" lib/
```

Expected: Find where binary content is read and potentially mixed with UTF-8

**Step 4: Document code location**

Add to investigation notes:

```markdown
## Code Analysis

### Generator Pipeline
1. File read location: [file:line]
2. Encoding conversion: [present/absent]
3. String operations: [list operations on binary data]

### Suspected Issue
[Exact line where binary/UTF-8 mixing occurs]
```

**Step 5: Commit updated investigation**

```bash
git add docs/investigations/encoding-error-2025-11-17.md
git commit -m "docs: add code analysis to encoding investigation"
```

---

## Task 3: Implement fix based on findings

**Files:**
- Will depend on investigation findings
- Likely: Generator's markdown processing or Hub's GCS upload

**Step 1: Write failing test**

Based on findings, create test that reproduces the error.

Example if issue is in file upload:

```ruby
# test/services/gcs_uploader_test.rb
test "handles binary content in markdown files" do
  uploader = GcsUploader.new("test-bucket", podcast_id: "test")

  # Create content with binary and UTF-8 mix
  binary_content = "\xFF\xFE".force_encoding("ASCII-8BIT")
  utf8_text = "Hello World"

  # This should not raise encoding error
  assert_nothing_raised do
    uploader.upload_staging_file(
      content: binary_content + utf8_text,
      filename: "test.md"
    )
  end
end
```

**Step 2: Run test to verify it fails**

```bash
rails test test/services/gcs_uploader_test.rb
```

Expected: FAIL with encoding error

**Step 3: Implement fix**

Common fix patterns:

**Option A: Force UTF-8 encoding on read**
```ruby
content = uploaded_file.read.force_encoding("UTF-8")
```

**Option B: Validate and sanitize**
```ruby
content = uploaded_file.read
content = content.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
```

**Option C: Ensure binary mode throughout**
```ruby
# If content should be binary
content = uploaded_file.read.force_encoding("BINARY")
# Keep binary until final text extraction
```

Apply appropriate fix based on investigation findings.

**Step 4: Run test to verify it passes**

```bash
rails test test/services/gcs_uploader_test.rb
```

Expected: PASS

**Step 5: Test with actual episode files**

```bash
# In Rails console
content = File.read("/tmp/episode-15.md")
# Try the fix
fixed_content = content.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
puts "Original encoding: #{content.encoding}"
puts "Fixed encoding: #{fixed_content.encoding}"
puts "Can concatenate with UTF-8: #{(fixed_content + " test").inspect}"
```

Expected: No encoding errors

**Step 6: Commit fix**

```bash
git add [files modified]
git commit -m "fix: handle binary content in episode file uploads

Properly converts binary/mixed encoding content to UTF-8 before
string operations to prevent incompatible encoding errors.

Fixes episodes 15 and 18 encoding errors"
```

---

## Task 4: Add retry mechanism for stuck episodes

**Files:**
- Create: `lib/tasks/episodes.rake`

**Step 1: Create rake task to retry failed episodes**

```ruby
# lib/tasks/episodes.rake
namespace :episodes do
  desc "Retry failed episodes"
  task retry_failed: :environment do
    failed_episodes = Episode.where(status: "failed")

    puts "Found #{failed_episodes.count} failed episodes"

    failed_episodes.each do |episode|
      puts "Retrying episode #{episode.id}: #{episode.title}"

      # Reset status
      episode.update(status: "pending", error_message: nil)

      # Re-enqueue if we have the staging path
      # This will depend on your system design
      puts "  Reset to pending - will be picked up by processor"
    end
  end

  desc "Clear stuck episodes (15 and 18 specifically)"
  task clear_stuck: :environment do
    [15, 18].each do |id|
      episode = Episode.find_by(id: id)
      next unless episode

      puts "Clearing episode #{id}"
      episode.update(status: "pending", error_message: nil)
    end
  end
end
```

**Step 2: Test rake task**

```bash
rails episodes:retry_failed
```

Expected: Episodes reset to pending

**Step 3: Commit**

```bash
git add lib/tasks/episodes.rake
git commit -m "feat: add rake task to retry failed episodes

Allows manual retry of episodes stuck in failed state"
```

---

## Task 5: Add encoding validation middleware

**Files:**
- Create: `app/services/encoding_validator.rb`
- Modify: `app/services/episode_submission_service.rb`

**Step 1: Write failing test**

```ruby
# test/services/encoding_validator_test.rb
require "test_helper"

class EncodingValidatorTest < ActiveSupport::TestCase
  test "validates UTF-8 content" do
    validator = EncodingValidator.new
    utf8_content = "Hello, World! 你好"

    result = validator.validate(utf8_content)

    assert result.valid?
    assert_equal "UTF-8", result.content.encoding.name
  end

  test "converts binary content to UTF-8" do
    validator = EncodingValidator.new
    binary_content = "\xFF\xFEHello".force_encoding("ASCII-8BIT")

    result = validator.validate(binary_content)

    assert result.valid?
    assert_equal "UTF-8", result.content.encoding.name
  end

  test "removes invalid UTF-8 sequences" do
    validator = EncodingValidator.new
    invalid_utf8 = "Hello\xFF\xFEWorld".force_encoding("UTF-8")

    result = validator.validate(invalid_utf8)

    assert result.valid?
    assert_includes result.content, "Hello"
    assert_includes result.content, "World"
  end
end
```

**Step 2: Run test to verify failure**

```bash
rails test test/services/encoding_validator_test.rb
```

Expected: FAIL - class not found

**Step 3: Implement EncodingValidator**

```ruby
# app/services/encoding_validator.rb
class EncodingValidator
  class Result
    attr_reader :content, :original_encoding, :warnings

    def initialize(content:, original_encoding:, warnings: [])
      @content = content
      @original_encoding = original_encoding
      @warnings = warnings
    end

    def valid?
      content.valid_encoding?
    end
  end

  def validate(content)
    original_encoding = content.encoding.name
    warnings = []

    # Convert to UTF-8, handling invalid sequences
    utf8_content = content.encode(
      "UTF-8",
      invalid: :replace,
      undef: :replace,
      replace: ""
    )

    # Warn if we had to replace characters
    if utf8_content.bytesize < content.bytesize
      warnings << "Removed invalid characters during encoding conversion"
    end

    Result.new(
      content: utf8_content,
      original_encoding: original_encoding,
      warnings: warnings
    )
  end
end
```

**Step 4: Run test to verify pass**

```bash
rails test test/services/encoding_validator_test.rb
```

Expected: PASS

**Step 5: Integrate into EpisodeSubmissionService**

```ruby
# app/services/episode_submission_service.rb
def upload_to_staging(episode)
  unless uploaded_file.respond_to?(:read)
    raise ArgumentError, "Invalid file upload - file must be readable"
  end

  raw_content = uploaded_file.read

  # Validate and fix encoding
  validation = EncodingValidator.new.validate(raw_content)
  content = validation.content

  # Log warnings if encoding was fixed
  if validation.warnings.any?
    Rails.logger.warn "event=encoding_fixed episode_id=#{episode.id} warnings=#{validation.warnings.join(', ')}"
  end

  filename = "#{episode.id}-#{Time.now.to_i}.md"
  staging_path = gcs_uploader.upload_staging_file(content: content, filename: filename)

  Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

  staging_path
end
```

**Step 6: Run full test suite**

```bash
rails test
```

Expected: All tests PASS

**Step 7: Commit**

```bash
git add app/services/encoding_validator.rb test/services/encoding_validator_test.rb app/services/episode_submission_service.rb
git commit -m "feat: add encoding validation for episode uploads

Automatically converts binary/mixed encoding content to UTF-8
and sanitizes invalid sequences. Prevents encoding errors in
downstream processing.

Resolves encoding errors for episodes 15, 18 and prevents future
occurrences"
```

---

## Verification

**Test with problematic episodes:**

1. Use rake task to retry episodes 15 and 18:
```bash
rails episodes:clear_stuck
```

2. Monitor logs for successful processing:
```bash
kamal app logs -f
```

3. Verify episodes complete successfully

**Test with new uploads:**

1. Create file with mixed encoding:
```bash
echo "Hello World" > /tmp/test.md
echo -ne "\xFF\xFE" >> /tmp/test.md
```

2. Upload via web interface

3. Verify no encoding errors

**Deployment:**
```bash
git push origin main
./bin/deploy
```
