# Improve Error Handling and User Messaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve error handling with structured error codes from Generator and user-friendly messages in Hub

**Architecture:**
- Generator API returns structured error responses with error codes and categories
- Hub Rails app maps error codes to user-friendly messages
- Fix encoding issues at system boundaries
- Change content filter behavior to fail entire episode (not skip chunks)

**Tech Stack:** Ruby (Sinatra API + Rails app), Google Cloud Text-to-Speech

---

## Task 1: Add defensive encoding at system boundaries (Generator)

**Files:**
- Modify: `api.rb`
- Modify: `lib/text_processor.rb`

**Step 1: Fix file upload encoding**

In `api.rb` around line 110:

```ruby
def handle_episode_submission(params)
  podcast_id = params[:podcast_id]
  title = params[:title]

  # Fix: Ensure UTF-8 encoding from uploaded file
  raw_content = params[:content][:tempfile].read
  markdown_content = raw_content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

  # Upload to staging
  staging_path = upload_to_staging(podcast_id: podcast_id, title: title, markdown_content: markdown_content)

  # Enqueue task
  enqueue_processing_task(params: params, staging_path: staging_path)
end
```

**Step 2: Fix error message logging in api.rb**

Around lines 58, 75, 78 - apply same fix as TTS error messages:

```ruby
rescue StandardError => e
  safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  logger.error "event=publish_error error_class=#{e.class} error_message=\"#{safe_message}\""
  logger.error "event=publish_error_backtrace backtrace=\"#{e.backtrace.first(5).join(' | ')}\""
  halt 500, json(status: "error", message: "Internal server error")
end
```

**Step 3: Write tests**

Create `test/test_encoding_safety.rb`:

```ruby
require "minitest/autorun"
require "rack/test"
require_relative "../api"

class TestEncodingSafety < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_handles_binary_file_upload
    # Create a tempfile with binary content
    binary_content = +"Test content with binary \xFF\xFE"
    binary_content.force_encoding("ASCII-8BIT")

    tempfile = Tempfile.new("test")
    tempfile.write(binary_content)
    tempfile.rewind

    # Should not crash with encoding error
    # (Will fail auth, but shouldn't crash on encoding)
    post "/publish", {
      content: { tempfile: tempfile, filename: "test.md" }
    }

    # Should get 401 (auth), not 500 (encoding crash)
    assert_equal 401, last_response.status
  end
end
```

**Step 4: Run tests**

```bash
ruby test/test_encoding_safety.rb
```

Expected: Pass

**Step 5: Commit**

```bash
git add api.rb test/test_encoding_safety.rb
git commit -m "fix: add defensive UTF-8 encoding at file upload boundary

Ensures binary or non-UTF-8 uploaded files don't cause encoding crashes.
Applies same safe encoding pattern used for TTS error messages."
```

---

## Task 2: Create error classification system (Generator)

**Files:**
- Create: `lib/error_classifier.rb`
- Create: `test/test_error_classifier.rb`

**Step 1: Create ErrorClassifier class**

```ruby
# lib/error_classifier.rb
class ErrorClassifier
  # Error categories for Hub to handle differently
  CATEGORIES = {
    invalid_input: "INVALID_INPUT",      # User can fix
    quota_exceeded: "QUOTA_EXCEEDED",    # Temporary, try later
    service_error: "SERVICE_ERROR",      # Not user's fault
    config_error: "CONFIG_ERROR",        # System misconfiguration
    unknown: "UNKNOWN"                   # Uncategorized
  }.freeze

  # Specific error codes
  CODES = {
    sentence_too_long: "SENTENCE_TOO_LONG",
    content_filter: "CONTENT_FILTER_VIOLATION",
    file_encoding: "FILE_ENCODING_ERROR",
    quota_exceeded: "QUOTA_EXCEEDED",
    timeout: "TIMEOUT",
    server_error: "SERVER_ERROR",
    service_unavailable: "SERVICE_UNAVAILABLE",
    auth_failed: "AUTH_FAILED",
    unknown: "UNKNOWN_ERROR"
  }.freeze

  def self.classify(error)
    error_message = safe_encode(error.message)

    case
    when error_message.include?("too long")
      {
        code: CODES[:sentence_too_long],
        category: CATEGORIES[:invalid_input],
        details: extract_sentence_details(error_message),
        recoverable: false
      }
    when error_message.include?("sensitive or harmful content")
      {
        code: CODES[:content_filter],
        category: CATEGORIES[:invalid_input],
        details: "Content flagged by safety filters",
        recoverable: false
      }
    when error.is_a?(Google::Cloud::ResourceExhaustedError)
      {
        code: CODES[:quota_exceeded],
        category: CATEGORIES[:quota_exceeded],
        details: "Daily API quota exceeded",
        recoverable: true
      }
    when error_message.include?("Deadline Exceeded")
      {
        code: CODES[:timeout],
        category: CATEGORIES[:service_error],
        details: "Request timed out",
        recoverable: true
      }
    when error.is_a?(Google::Cloud::InternalError)
      {
        code: CODES[:server_error],
        category: CATEGORIES[:service_error],
        details: "Upstream service error",
        recoverable: true
      }
    when error.is_a?(Google::Cloud::UnavailableError)
      {
        code: CODES[:service_unavailable],
        category: CATEGORIES[:service_error],
        details: "Service temporarily unavailable",
        recoverable: true
      }
    when error.is_a?(Google::Cloud::UnauthenticatedError)
      {
        code: CODES[:auth_failed],
        category: CATEGORIES[:config_error],
        details: "Authentication failed",
        recoverable: false
      }
    when error_message.include?("encoding") || error.is_a?(Encoding::CompatibilityError)
      {
        code: CODES[:file_encoding],
        category: CATEGORIES[:invalid_input],
        details: "File encoding incompatible",
        recoverable: false
      }
    else
      {
        code: CODES[:unknown],
        category: CATEGORIES[:unknown],
        details: error_message,
        recoverable: false
      }
    end
  end

  private

  def self.safe_encode(message)
    message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  end

  def self.extract_sentence_details(error_message)
    # Extract the problematic sentence from error like:
    # "Sentence starting with: 'Five(' is too long"
    if error_message =~ /Sentence starting with: ['"](.+?)['"]/
      "Sentence starting with: #{$1}"
    else
      "One or more sentences too long"
    end
  end
end
```

**Step 2: Write tests**

Create `test/test_error_classifier.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/error_classifier"

class TestErrorClassifier < Minitest::Test
  def test_classifies_sentence_too_long
    error = StandardError.new("This request contains sentences that are too long. Sentence starting with: 'Five(' is too long.")

    result = ErrorClassifier.classify(error)

    assert_equal "SENTENCE_TOO_LONG", result[:code]
    assert_equal "INVALID_INPUT", result[:category]
    assert_includes result[:details], "Five("
    refute result[:recoverable]
  end

  def test_classifies_content_filter
    error = StandardError.new("Error with sensitive or harmful content")

    result = ErrorClassifier.classify(error)

    assert_equal "CONTENT_FILTER_VIOLATION", result[:code]
    assert_equal "INVALID_INPUT", result[:category]
  end

  def test_classifies_quota_exceeded
    error = Google::Cloud::ResourceExhaustedError.new("quota exceeded")

    result = ErrorClassifier.classify(error)

    assert_equal "QUOTA_EXCEEDED", result[:code]
    assert result[:recoverable]
  end

  def test_classifies_timeout
    error = StandardError.new("Deadline Exceeded")

    result = ErrorClassifier.classify(error)

    assert_equal "TIMEOUT", result[:code]
    assert_equal "SERVICE_ERROR", result[:category]
  end

  def test_handles_binary_error_messages
    binary_message = +"API error: \xFF\xFE binary data"
    binary_message.force_encoding("ASCII-8BIT")
    error = StandardError.new(binary_message)

    result = ErrorClassifier.classify(error)

    # Should not crash with encoding error
    assert_equal "UNKNOWN_ERROR", result[:code]
    assert result[:details].is_a?(String)
  end
end
```

**Step 3: Run tests**

```bash
ruby test/test_error_classifier.rb
```

Expected: All pass

**Step 4: Commit**

```bash
git add lib/error_classifier.rb test/test_error_classifier.rb
git commit -m "feat: add error classification system

Maps TTS API errors to structured error codes with categories.
Enables Hub to show user-friendly messages based on error type."
```

---

## Task 3: Update API to return structured errors

**Files:**
- Modify: `api.rb`
- Modify: `lib/error_classifier.rb`

**Step 1: Update process_episode_task error handling**

In `api.rb`, modify the rescue block around line 188:

```ruby
def process_episode_task(payload)
  podcast_id = payload["podcast_id"]
  # ... existing code ...

  processor = EpisodeProcessor.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"), podcast_id)
  episode_data = processor.process(title: title, author: author, description: description,
                                   markdown_content: markdown_content)
  # ... success handling ...
rescue StandardError => e
  # Classify the error
  error_info = ErrorClassifier.classify(e)

  # Notify Hub with structured error
  if episode_id
    notify_hub_failed(
      episode_id: episode_id,
      error_code: error_info[:code],
      error_category: error_info[:category],
      error_details: error_info[:details],
      recoverable: error_info[:recoverable]
    )
  end

  # Log structured error
  logger.error log_event(:process_error,
    error_code: error_info[:code],
    error_category: error_info[:category],
    error_class: e.class.name,
    podcast_id: podcast_id,
    episode_id: episode_id
  )

  raise
end
```

**Step 2: Update notify_hub_failed signature**

```ruby
def notify_hub_failed(episode_id:, error_code:, error_category:, error_details:, recoverable:)
  hub_url = ENV.fetch("HUB_CALLBACK_URL", nil)
  callback_secret = ENV.fetch("HUB_CALLBACK_SECRET", nil)

  return unless hub_url && callback_secret

  client = HubCallbackClient.new(hub_url: hub_url, callback_secret: callback_secret)
  response = client.notify_failed(
    episode_id: episode_id,
    error_code: error_code,
    error_category: error_category,
    error_details: error_details,
    recoverable: recoverable
  )
  logger.info log_event(:hub_failure_notified, episode_id: episode_id, status: response.code)
rescue StandardError => e
  logger.error log_event(:hub_callback_error, episode_id: episode_id, error: e.message)
end
```

**Step 3: Update HubCallbackClient**

In `lib/hub_callback_client.rb`:

```ruby
def notify_failed(episode_id:, error_code:, error_category:, error_details:, recoverable:)
  payload = {
    episode_id: episode_id,
    status: "failed",
    error_code: error_code,
    error_category: error_category,
    error_details: error_details,
    recoverable: recoverable
  }

  make_request(payload)
end
```

**Step 4: Commit**

```bash
git add api.rb lib/hub_callback_client.rb
git commit -m "feat: return structured error codes to Hub

Hub now receives error_code, error_category, error_details, and
recoverable flag instead of just error_message. Enables better
user-facing error messages."
```

---

## Task 4: Change content filter to fail episode (Generator)

**Files:**
- Modify: `lib/tts/chunked_synthesizer.rb`

**Step 1: Update handle_chunk_error to fail on content filter**

Replace the current content filter skip logic:

```ruby
def handle_chunk_error(error:, chunk_num:, total:, skipped_chunks:)
  # Convert error message to UTF-8 safely to prevent encoding errors when logging
  safe_message = error.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

  # Content filter violations now fail the entire episode
  if safe_message.include?(CONTENT_FILTER_ERROR)
    @logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - Content filter violation"
    raise # Changed from skip to fail
  else
    @logger.error "Chunk #{chunk_num}/#{total}: ✗ Failed - #{safe_message}"
    raise
  end
end
```

**Step 2: Remove skipped_chunks tracking (no longer needed)**

In `launch_chunk_promises`, remove the `skipped_chunks` array since we're no longer skipping:

```ruby
def launch_chunk_promises(chunks:, voice:, pool:)
  promises = []
  total = chunks.length

  chunks.each_with_index do |chunk, i|
    promise = Concurrent::Promise.execute(executor: pool) do
      process_chunk(chunk: chunk, index: i, total: total, voice: voice)
    end
    promises << promise
  end

  promises
end

def process_chunk(chunk:, index:, total:, voice:)
  chunk_num = index + 1
  @logger.info "Chunk #{chunk_num}/#{total}: Starting (#{chunk.bytesize} bytes)"

  chunk_start = Time.now
  audio = synthesize_chunk_with_error_handling(chunk: chunk, chunk_num: chunk_num, total: total, voice: voice)

  log_chunk_completion(chunk_num: chunk_num, total: total, chunk_start: chunk_start) if audio

  [index, audio]
end

def synthesize_chunk_with_error_handling(chunk:, chunk_num:, total:, voice:)
  @api_client.call_with_retry(text: chunk, voice: voice, max_retries: @config.max_retries)
rescue StandardError => e
  handle_chunk_error(error: e, chunk_num: chunk_num, total: total)
  nil
end
```

**Step 3: Update tests**

Modify `test/test_chunked_synthesizer.rb`:

```ruby
def test_synthesize_fails_on_content_filter
  chunks = ["Safe chunk.", "Filtered chunk.", "Another safe chunk."]
  voice = "en-GB-Chirp3-HD-Enceladus"

  @mock_api_client.expect :call_with_retry, "audio1" do |**_kwargs|
    true
  end

  @mock_api_client.expect :call_with_retry, nil do |**_kwargs|
    raise StandardError, "Error with sensitive or harmful content"
  end

  # Should now raise error instead of skipping
  error = assert_raises(StandardError) do
    @synthesizer.synthesize(chunks, voice)
  end

  assert_includes error.message, "sensitive or harmful content"
end
```

Remove or update the old `test_synthesize_skips_content_filtered_chunks` test.

**Step 4: Run tests**

```bash
ruby test/test_chunked_synthesizer.rb
```

Expected: All pass with updated behavior

**Step 5: Commit**

```bash
git add lib/tts/chunked_synthesizer.rb test/test_chunked_synthesizer.rb
git commit -m "fix: fail entire episode on content filter violation

Changed from skipping filtered chunks to failing entire episode.
Prevents publishing partial/incomplete audio with missing sections."
```

---

## Task 5: Add error message mapping in Hub (Rails)

**Files:**
- Create: `app/services/error_message_mapper.rb`
- Create: `test/services/error_message_mapper_test.rb`
- Modify: `app/models/episode.rb`

**Step 1: Create ErrorMessageMapper service**

```ruby
# app/services/error_message_mapper.rb
class ErrorMessageMapper
  ERROR_MESSAGES = {
    "SENTENCE_TOO_LONG" => {
      title: "Unable to generate audio",
      message: "One or more sentences exceed the maximum length.\n\nNext steps:\n• Review sentences in your content\n• Break long sentences into shorter ones using periods\n• Re-submit your content",
      user_action_required: true
    },
    "CONTENT_FILTER_VIOLATION" => {
      title: "Content policy violation",
      message: "Unable to process text. The content was flagged as a potential terms of service violation. Submit another file.",
      user_action_required: true
    },
    "QUOTA_EXCEEDED" => {
      title: "Service quota exceeded",
      message: "Text to speech quota exceeded. Try again tomorrow.",
      user_action_required: false
    },
    "TIMEOUT" => {
      title: "Processing timeout",
      message: "Processing timed out. Please try again.",
      user_action_required: true
    },
    "SERVER_ERROR" => {
      title: "Server error",
      message: "The text-to-speech service encountered an internal problem. This is not your fault. Please try again in a few minutes.",
      user_action_required: false
    },
    "SERVICE_UNAVAILABLE" => {
      title: "Service unavailable",
      message: "Service temporarily unavailable. Please try again in a few minutes.",
      user_action_required: false
    },
    "FILE_ENCODING_ERROR" => {
      title: "File encoding error",
      message: "We couldn't read your file. This usually means it was saved with an incompatible text encoding.\n\nHow to fix:\n1. Open your file in a text editor\n2. Save As → Choose UTF-8 encoding\n3. Re-upload",
      user_action_required: true
    },
    "AUTH_FAILED" => {
      title: "Service error",
      message: "Service configuration error. Our team has been notified.",
      user_action_required: false
    },
    "UNKNOWN_ERROR" => {
      title: "Unexpected error",
      message: "An unexpected error occurred. Please try again or contact support.",
      user_action_required: true
    }
  }.freeze

  def self.map(error_code, error_details = nil)
    mapping = ERROR_MESSAGES[error_code] || ERROR_MESSAGES["UNKNOWN_ERROR"]

    # For sentence too long, include specific details if available
    if error_code == "SENTENCE_TOO_LONG" && error_details.present?
      mapping = mapping.dup
      mapping[:message] = mapping[:message].sub(
        "Review sentences in your content",
        "Review sentences in your content (specifically: #{error_details})"
      )
    end

    mapping
  end
end
```

**Step 2: Write tests**

```ruby
# test/services/error_message_mapper_test.rb
require "test_helper"

class ErrorMessageMapperTest < ActiveSupport::TestCase
  test "maps sentence too long error" do
    result = ErrorMessageMapper.map("SENTENCE_TOO_LONG", "Sentence starting with: Five(")

    assert_equal "Unable to generate audio", result[:title]
    assert_includes result[:message], "Five("
    assert result[:user_action_required]
  end

  test "maps content filter violation" do
    result = ErrorMessageMapper.map("CONTENT_FILTER_VIOLATION")

    assert_equal "Content policy violation", result[:title]
    assert_includes result[:message], "terms of service"
    assert result[:user_action_required]
  end

  test "maps quota exceeded" do
    result = ErrorMessageMapper.map("QUOTA_EXCEEDED")

    assert_includes result[:message], "tomorrow"
    refute result[:user_action_required]
  end

  test "returns unknown error for unrecognized code" do
    result = ErrorMessageMapper.map("WEIRD_ERROR_CODE")

    assert_equal "Unexpected error", result[:title]
    assert result[:user_action_required]
  end
end
```

**Step 3: Update Episode model to store structured error**

In `app/models/episode.rb`, modify the callback handler:

```ruby
def handle_generator_callback(params)
  if params[:status] == "complete"
    update!(
      status: "complete",
      gcs_episode_id: params[:gcs_episode_id],
      audio_url: params[:audio_url],
      error_message: nil,
      error_code: nil,
      error_category: nil
    )
  elsif params[:status] == "failed"
    error_mapping = ErrorMessageMapper.map(params[:error_code], params[:error_details])

    update!(
      status: "failed",
      error_code: params[:error_code],
      error_category: params[:error_category],
      error_message: error_mapping[:message],
      error_title: error_mapping[:title],
      user_action_required: error_mapping[:user_action_required]
    )
  end
end
```

**Step 4: Add database migration**

```bash
cd hub
rails generate migration AddStructuredErrorsToEpisodes error_code:string error_category:string error_title:string user_action_required:boolean
```

Edit the migration:

```ruby
class AddStructuredErrorsToEpisodes < ActiveRecord::Migration[8.0]
  def change
    add_column :episodes, :error_code, :string
    add_column :episodes, :error_category, :string
    add_column :episodes, :error_title, :string
    add_column :episodes, :user_action_required, :boolean, default: false

    add_index :episodes, :error_code
    add_index :episodes, :error_category
  end
end
```

Run migration:

```bash
rails db:migrate
```

**Step 5: Update episode show view to display structured errors**

In `app/views/episodes/show.html.erb`, replace error display:

```erb
<% if @episode.failed? %>
  <div class="error-box">
    <h3><%= @episode.error_title || "Processing Failed" %></h3>
    <p><%= simple_format(@episode.error_message) %></p>

    <% if @episode.user_action_required? %>
      <div class="error-actions">
        <%= link_to "Edit Episode", edit_episode_path(@episode), class: "btn btn-primary" %>
      </div>
    <% else %>
      <p class="error-hint">This is a temporary issue. Please try again later.</p>
    <% end %>
  </div>
<% end %>
```

**Step 6: Run tests**

```bash
cd hub
rails test
```

Expected: All pass

**Step 7: Commit**

```bash
git add app/services/error_message_mapper.rb test/services/error_message_mapper_test.rb app/models/episode.rb app/views/episodes/show.html.erb db/migrate/*
git commit -m "feat: add user-friendly error message mapping in Hub

Maps Generator error codes to user-friendly messages.
Stores structured error info (code, category, title) in database.
Shows actionable messages to users based on error type."
```

---

## Verification

**Test the complete flow:**

1. **Encoding safety**: Upload a file with binary content
   - Should not crash with encoding error
   - Should process or fail gracefully

2. **Sentence too long error**: Create episode with very long sentence
   - Generator should return `SENTENCE_TOO_LONG` code
   - Hub should show: "Unable to generate audio: One or more sentences..."
   - User should see actionable steps

3. **Content filter**: Create episode with content that triggers filter
   - Generator should fail entire episode (not skip chunks)
   - Hub should show: "Content policy violation..."
   - Episode should be marked failed

4. **Service errors**: Simulate by breaking API credentials temporarily
   - Should return `AUTH_FAILED` code
   - Hub should show generic "Service configuration error"
   - Should not expose auth details to user

**Deployment:**

```bash
# Generator (API)
cd /path/to/tts
git push origin main
./bin/deploy  # Deploys to Cloud Run

# Hub (Rails)
cd /path/to/tts/hub
git push origin main
./bin/deploy  # Deploys Hub to Cloud Run
rails db:migrate  # Run on production
```

---

## Notes

- All error messages are now consistent and user-friendly
- Generator returns structured error codes, Hub maps to messages
- Content filter now fails entire episode (breaking change!)
- Encoding safety added at all system boundaries
- Future enhancements in braindump.md: auto-retry, file validation, error IDs
