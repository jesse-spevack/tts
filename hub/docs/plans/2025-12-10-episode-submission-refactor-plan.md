# Episode Submission Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split `UploadAndEnqueueEpisode` into focused single-responsibility services, create `SubmitEpisodeForProcessing` orchestrator, and align the markdown upload path with URL/Paste async patterns.

**Architecture:** Extract upload and enqueue into separate services. Create `SubmitEpisodeForProcessing` that composes `BuildEpisodeWrapper` → `UploadEpisodeContent` → `EnqueueEpisodeProcessing`. Create `CreateMarkdownEpisode`, `ProcessMarkdownEpisodeJob`, and `ProcessMarkdownEpisode` to align the markdown path with URL/Paste. Delete `UploadAndEnqueueEpisode` and `EpisodeSubmissionService`.

**Tech Stack:** Ruby on Rails, Minitest with Mocktail

---

## Task 1: Create UploadEpisodeContent Service

**Files:**
- Create: `hub/app/services/upload_episode_content.rb`
- Create: `hub/test/services/upload_episode_content_test.rb`

### Step 1: Write the failing test

Create `hub/test/services/upload_episode_content_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class UploadEpisodeContentTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
    Mocktail.replace(GcsUploader)
  end

  test "uploads content to GCS and returns staging path" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/123-456.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    result = UploadEpisodeContent.call(episode: @episode, content: "Test content")

    assert_equal "staging/123-456.txt", result
    verify { |m| mock_gcs.upload_staging_file(content: "Test content", filename: m.any) }
  end

  test "generates filename with episode id and timestamp" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    UploadEpisodeContent.call(episode: @episode, content: "Test content")

    verify { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.that { |f| f.start_with?("#{@episode.id}-") && f.end_with?(".txt") }) }
  end

  test "initializes GcsUploader with bucket and podcast_id" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    UploadEpisodeContent.call(episode: @episode, content: "Test content")

    verify { GcsUploader.new("test-bucket", podcast_id: @episode.podcast.podcast_id) }
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/upload_episode_content_test.rb`

Expected: FAIL with `NameError: uninitialized constant UploadEpisodeContent`

### Step 3: Write the implementation

Create `hub/app/services/upload_episode_content.rb`:

```ruby
# frozen_string_literal: true

class UploadEpisodeContent
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    filename = "#{episode.id}-#{Time.now.to_i}.txt"
    gcs_uploader.upload_staging_file(content: content, filename: filename)
  end

  private

  attr_reader :episode, :content

  def gcs_uploader
    @gcs_uploader ||= GcsUploader.new(
      ENV.fetch("GOOGLE_CLOUD_BUCKET"),
      podcast_id: episode.podcast.podcast_id
    )
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/upload_episode_content_test.rb`

Expected: 3 tests, 0 failures

### Step 5: Commit

```bash
git add app/services/upload_episode_content.rb test/services/upload_episode_content_test.rb
git commit -m "feat: add UploadEpisodeContent service"
```

---

## Task 2: Create EnqueueEpisodeProcessing Service

**Files:**
- Create: `hub/app/services/enqueue_episode_processing.rb`
- Create: `hub/test/services/enqueue_episode_processing_test.rb`

### Step 1: Write the failing test

Create `hub/test/services/enqueue_episode_processing_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EnqueueEpisodeProcessingTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(title: "Test Title", author: "Test Author", description: "Test desc")
    Mocktail.replace(CloudTasksEnqueuer)
  end

  test "enqueues episode for processing via Cloud Tasks" do
    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    result = EnqueueEpisodeProcessing.call(episode: @episode, staging_path: "staging/test.txt")

    assert_equal "task-123", result
  end

  test "passes correct episode metadata" do
    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    EnqueueEpisodeProcessing.call(episode: @episode, staging_path: "staging/test.txt")

    expected_metadata = { title: "Test Title", author: "Test Author", description: "Test desc" }
    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: @episode.id, podcast_id: @episode.podcast.podcast_id, staging_path: "staging/test.txt", metadata: expected_metadata, voice_name: m.any) }
  end

  test "passes episode voice" do
    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    EnqueueEpisodeProcessing.call(episode: @episode, staging_path: "staging/test.txt")

    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: @episode.voice) }
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/enqueue_episode_processing_test.rb`

Expected: FAIL with `NameError: uninitialized constant EnqueueEpisodeProcessing`

### Step 3: Write the implementation

Create `hub/app/services/enqueue_episode_processing.rb`:

```ruby
# frozen_string_literal: true

class EnqueueEpisodeProcessing
  def self.call(episode:, staging_path:)
    new(episode: episode, staging_path: staging_path).call
  end

  def initialize(episode:, staging_path:)
    @episode = episode
    @staging_path = staging_path
  end

  def call
    tasks_enqueuer.enqueue_episode_processing(
      episode_id: episode.id,
      podcast_id: episode.podcast.podcast_id,
      staging_path: staging_path,
      metadata: {
        title: episode.title,
        author: episode.author,
        description: episode.description
      },
      voice_name: episode.voice
    )
  end

  private

  attr_reader :episode, :staging_path

  def tasks_enqueuer
    @tasks_enqueuer ||= CloudTasksEnqueuer.new
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/enqueue_episode_processing_test.rb`

Expected: 3 tests, 0 failures

### Step 5: Commit

```bash
git add app/services/enqueue_episode_processing.rb test/services/enqueue_episode_processing_test.rb
git commit -m "feat: add EnqueueEpisodeProcessing service"
```

---

## Task 3: Create SubmitEpisodeForProcessing Orchestrator

**Files:**
- Create: `hub/app/services/submit_episode_for_processing.rb`
- Create: `hub/test/services/submit_episode_for_processing_test.rb`

### Step 1: Write the failing test

Create `hub/test/services/submit_episode_for_processing_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class SubmitEpisodeForProcessingTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(title: "Test Title", author: "Test Author")
    @episode.user.update!(tier: :free)
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    Mocktail.replace(GcsUploader)
    Mocktail.replace(CloudTasksEnqueuer)
  end

  test "wraps content, uploads, and enqueues for processing" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    SubmitEpisodeForProcessing.call(episode: @episode, content: "Article body.")

    expected_content = <<~EXPECTED.strip
      Test Title; by Test Author. This audio was generated by Very Normal TTS.

      Article body.

      Thank you for listening to this Very Normal TTS generated audio.
    EXPECTED

    verify { |m| mock_gcs.upload_staging_file(content: expected_content, filename: m.any) }
    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: @episode.id, podcast_id: m.any, staging_path: "staging/test.txt", metadata: m.any, voice_name: m.any) }
  end

  test "wraps content without free tier attribution for premium users" do
    @episode.user.update!(tier: :premium)

    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    SubmitEpisodeForProcessing.call(episode: @episode, content: "Article body.")

    expected_content = <<~EXPECTED.strip
      Test Title; by Test Author.

      Article body.

      Thank you for listening to this Very Normal TTS generated audio.
    EXPECTED

    verify { |m| mock_gcs.upload_staging_file(content: expected_content, filename: m.any) }
  end

  test "logs staging upload and enqueue events" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    # Just verify it doesn't raise - logging is a side effect
    assert_nothing_raised do
      SubmitEpisodeForProcessing.call(episode: @episode, content: "Test content")
    end
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/submit_episode_for_processing_test.rb`

Expected: FAIL with `NameError: uninitialized constant SubmitEpisodeForProcessing`

### Step 3: Write the implementation

Create `hub/app/services/submit_episode_for_processing.rb`:

```ruby
# frozen_string_literal: true

class SubmitEpisodeForProcessing
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    wrapped_content = wrap_content
    staging_path = upload_content(wrapped_content)

    Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

    enqueue_processing(staging_path)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  private

  attr_reader :episode, :content

  def wrap_content
    BuildEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      tier: episode.user.tier,
      content: content
    )
  end

  def upload_content(wrapped_content)
    UploadEpisodeContent.call(episode: episode, content: wrapped_content)
  end

  def enqueue_processing(staging_path)
    EnqueueEpisodeProcessing.call(episode: episode, staging_path: staging_path)
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/submit_episode_for_processing_test.rb`

Expected: 3 tests, 0 failures

### Step 5: Commit

```bash
git add app/services/submit_episode_for_processing.rb test/services/submit_episode_for_processing_test.rb
git commit -m "feat: add SubmitEpisodeForProcessing orchestrator"
```

---

## Task 4: Update ProcessUrlEpisode to Use SubmitEpisodeForProcessing

**Files:**
- Modify: `hub/app/services/process_url_episode.rb`
- Modify: `hub/test/services/process_url_episode_test.rb`

### Step 1: Update the service

In `hub/app/services/process_url_episode.rb`, change line 100 from:

```ruby
      UploadAndEnqueueEpisode.call(episode: episode, content: content)
```

to:

```ruby
      SubmitEpisodeForProcessing.call(episode: episode, content: content)
```

### Step 2: Update the test

In `hub/test/services/process_url_episode_test.rb`, find and replace all occurrences of `UploadAndEnqueueEpisode` with `SubmitEpisodeForProcessing`.

### Step 3: Run tests to verify they pass

Run: `bin/rails test test/services/process_url_episode_test.rb`

Expected: All tests pass

### Step 4: Commit

```bash
git add app/services/process_url_episode.rb test/services/process_url_episode_test.rb
git commit -m "refactor: update ProcessUrlEpisode to use SubmitEpisodeForProcessing"
```

---

## Task 5: Update ProcessPasteEpisode to Use SubmitEpisodeForProcessing

**Files:**
- Modify: `hub/app/services/process_paste_episode.rb`
- Modify: `hub/test/services/process_paste_episode_test.rb`

### Step 1: Update the service

In `hub/app/services/process_paste_episode.rb`, change line 67 from:

```ruby
      UploadAndEnqueueEpisode.call(episode: episode, content: content)
```

to:

```ruby
      SubmitEpisodeForProcessing.call(episode: episode, content: content)
```

### Step 2: Update the test

In `hub/test/services/process_paste_episode_test.rb`, find and replace all occurrences of `UploadAndEnqueueEpisode` with `SubmitEpisodeForProcessing`.

### Step 3: Run tests to verify they pass

Run: `bin/rails test test/services/process_paste_episode_test.rb`

Expected: All tests pass

### Step 4: Commit

```bash
git add app/services/process_paste_episode.rb test/services/process_paste_episode_test.rb
git commit -m "refactor: update ProcessPasteEpisode to use SubmitEpisodeForProcessing"
```

---

## Task 6: Create CreateMarkdownEpisode Service

**Files:**
- Create: `hub/app/services/create_markdown_episode.rb`
- Create: `hub/test/services/create_markdown_episode_test.rb`

### Step 1: Write the failing test

Create `hub/test/services/create_markdown_episode_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CreateMarkdownEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
  end

  test "creates episode with markdown source type" do
    result = CreateMarkdownEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test Title",
      author: "Test Author",
      description: "Test description",
      content: "# Markdown content"
    )

    assert result.success?
    assert_equal :markdown, result.episode.source_type.to_sym
    assert_equal "Test Title", result.episode.title
    assert_equal "Test Author", result.episode.author
    assert_equal "Test description", result.episode.description
    assert_equal "# Markdown content", result.episode.source_text
  end

  test "sets episode status to processing" do
    result = CreateMarkdownEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: "Content here"
    )

    assert_equal "processing", result.episode.status
  end

  test "enqueues ProcessMarkdownEpisodeJob" do
    assert_enqueued_with(job: ProcessMarkdownEpisodeJob) do
      CreateMarkdownEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Test",
        author: "Author",
        description: "Desc",
        content: "Content here"
      )
    end
  end

  test "returns failure when content is blank" do
    result = CreateMarkdownEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: ""
    )

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
  end

  test "returns failure when content exceeds max characters" do
    @user.update!(tier: :free)
    max_chars = MaxCharactersForUser.call(user: @user)
    long_content = "a" * (max_chars + 1)

    result = CreateMarkdownEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )

    assert result.failure?
    assert_includes result.error, "too long"
  end

  test "sets content preview" do
    result = CreateMarkdownEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: "# Header\n\nSome markdown content here."
    )

    assert result.episode.content_preview.present?
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/create_markdown_episode_test.rb`

Expected: FAIL with `NameError: uninitialized constant CreateMarkdownEpisode`

### Step 3: Write the implementation

Create `hub/app/services/create_markdown_episode.rb`:

```ruby
# frozen_string_literal: true

class CreateMarkdownEpisode
  def self.call(podcast:, user:, title:, author:, description:, content:)
    new(podcast: podcast, user: user, title: title, author: author, description: description, content: content).call
  end

  def initialize(podcast:, user:, title:, author:, description:, content:)
    @podcast = podcast
    @user = user
    @title = title
    @author = author
    @description = description
    @content = content
  end

  def call
    return Result.failure("Content cannot be empty") if content.blank?
    return Result.failure(max_characters_error) if exceeds_max_characters?

    episode = create_episode
    ProcessMarkdownEpisodeJob.perform_later(episode.id)

    Rails.logger.info "event=markdown_episode_created episode_id=#{episode.id} content_length=#{content.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :title, :author, :description, :content

  def exceeds_max_characters?
    max_chars = MaxCharactersForUser.call(user: user)
    max_chars && content.length > max_chars
  end

  def max_characters_error
    max_chars = MaxCharactersForUser.call(user: user)
    "Content is too long for your account tier (#{content.length} characters, max #{max_chars})"
  end

  def create_episode
    plain_text = MarkdownStripper.strip(content)

    podcast.episodes.create!(
      user: user,
      title: title,
      author: author,
      description: description,
      source_type: :markdown,
      source_text: content,
      content_preview: ContentPreview.generate(plain_text),
      status: :processing
    )
  end

  class Result
    attr_reader :episode, :error

    def self.success(episode)
      new(episode: episode, error: nil)
    end

    def self.failure(error)
      new(episode: nil, error: error)
    end

    def initialize(episode:, error:)
      @episode = episode
      @error = error
    end

    def success?
      error.nil?
    end

    def failure?
      !success?
    end
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/create_markdown_episode_test.rb`

Expected: Tests will fail because `ProcessMarkdownEpisodeJob` doesn't exist yet. That's expected - we'll create it in Task 7.

### Step 5: Commit (partial - job coming next)

```bash
git add app/services/create_markdown_episode.rb test/services/create_markdown_episode_test.rb
git commit -m "feat: add CreateMarkdownEpisode service (job pending)"
```

---

## Task 7: Create ProcessMarkdownEpisodeJob

**Files:**
- Create: `hub/app/jobs/process_markdown_episode_job.rb`
- Create: `hub/test/jobs/process_markdown_episode_job_test.rb`

### Step 1: Write the failing test

Create `hub/test/jobs/process_markdown_episode_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessMarkdownEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(source_type: :markdown, source_text: "# Test markdown")
    Mocktail.replace(ProcessMarkdownEpisode)
  end

  test "calls ProcessMarkdownEpisode with episode" do
    stubs { |m| ProcessMarkdownEpisode.call(episode: m.any) }.with { nil }

    ProcessMarkdownEpisodeJob.perform_now(@episode.id)

    verify { ProcessMarkdownEpisode.call(episode: @episode) }
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/jobs/process_markdown_episode_job_test.rb`

Expected: FAIL with `NameError: uninitialized constant ProcessMarkdownEpisodeJob`

### Step 3: Write the implementation

Create `hub/app/jobs/process_markdown_episode_job.rb`:

```ruby
# frozen_string_literal: true

class ProcessMarkdownEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    Rails.logger.info "event=process_markdown_episode_job_started episode_id=#{episode_id}"

    episode = Episode.find(episode_id)
    ProcessMarkdownEpisode.call(episode: episode)

    Rails.logger.info "event=process_markdown_episode_job_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=process_markdown_episode_job_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/jobs/process_markdown_episode_job_test.rb`

Expected: Will fail because `ProcessMarkdownEpisode` service doesn't exist. That's expected.

### Step 5: Commit (partial - service coming next)

```bash
git add app/jobs/process_markdown_episode_job.rb test/jobs/process_markdown_episode_job_test.rb
git commit -m "feat: add ProcessMarkdownEpisodeJob (service pending)"
```

---

## Task 8: Create ProcessMarkdownEpisode Service

**Files:**
- Create: `hub/app/services/process_markdown_episode.rb`
- Create: `hub/test/services/process_markdown_episode_test.rb`

### Step 1: Write the failing test

Create `hub/test/services/process_markdown_episode_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessMarkdownEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(
      source_type: :markdown,
      source_text: "# Test Header\n\nSome **bold** content.",
      title: "Test Title",
      author: "Test Author"
    )

    Mocktail.replace(SubmitEpisodeForProcessing)
  end

  test "strips markdown and submits for processing" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { nil }

    ProcessMarkdownEpisode.call(episode: @episode)

    verify { |m| SubmitEpisodeForProcessing.call(episode: @episode, content: "Test Header\n\nSome bold content.") }
  end

  test "marks episode as failed on error" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { raise StandardError, "Upload failed" }

    ProcessMarkdownEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Upload failed", @episode.error_message
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/process_markdown_episode_test.rb`

Expected: FAIL with `NameError: uninitialized constant ProcessMarkdownEpisode`

### Step 3: Write the implementation

Create `hub/app/services/process_markdown_episode.rb`:

```ruby
# frozen_string_literal: true

class ProcessMarkdownEpisode
  include EpisodeLogging

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    log_info "process_markdown_episode_started", text_length: episode.source_text.length

    content = strip_markdown
    submit_for_processing(content)

    log_info "process_markdown_episode_completed"
  rescue StandardError => e
    log_error "process_markdown_episode_error", error: e.class, message: e.message
    fail_episode(e.message)
  end

  private

  attr_reader :episode

  def strip_markdown
    MarkdownStripper.strip(episode.source_text)
  end

  def submit_for_processing(content)
    SubmitEpisodeForProcessing.call(episode: episode, content: content)
  end

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    log_warn "episode_marked_failed", error: error_message
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/process_markdown_episode_test.rb`

Expected: 2 tests, 0 failures

### Step 5: Run CreateMarkdownEpisode tests again

Run: `bin/rails test test/services/create_markdown_episode_test.rb`

Expected: All tests pass now that the job and service exist

### Step 6: Commit

```bash
git add app/services/process_markdown_episode.rb test/services/process_markdown_episode_test.rb
git commit -m "feat: add ProcessMarkdownEpisode service"
```

---

## Task 9: Add markdown to Episode source_type enum

**Files:**
- Check: `hub/app/models/episode.rb`

### Step 1: Check if markdown is already in the enum

Read `hub/app/models/episode.rb` and look for the `source_type` enum definition.

If `markdown` is not present, add it:

```ruby
enum :source_type, { url: 0, paste: 1, markdown: 2 }
```

### Step 2: Run tests to verify

Run: `bin/rails test`

Expected: All tests pass

### Step 3: Commit if changes were made

```bash
git add app/models/episode.rb
git commit -m "feat: add markdown to Episode source_type enum"
```

---

## Task 10: Update EpisodesController to Use CreateMarkdownEpisode

**Files:**
- Modify: `hub/app/controllers/episodes_controller.rb`
- Modify: `hub/test/controllers/episodes_controller_test.rb` (if exists)

### Step 1: Update the controller

Replace the `create_from_markdown` method in `hub/app/controllers/episodes_controller.rb`:

```ruby
def create_from_markdown
  result = CreateMarkdownEpisode.call(
    podcast: @podcast,
    user: Current.user,
    title: episode_params[:title],
    author: episode_params[:author],
    description: episode_params[:description],
    content: read_uploaded_content
  )

  if result.success?
    RecordEpisodeUsage.call(user: Current.user)
    redirect_to episodes_path, notice: "Episode created! Processing..."
  else
    flash.now[:alert] = result.error
    @episode = @podcast.episodes.build
    render :new, status: :unprocessable_entity
  end
end

private

def read_uploaded_content
  return nil unless params[:episode][:content]&.respond_to?(:read)

  params[:episode][:content].read
end
```

### Step 2: Run controller tests

Run: `bin/rails test test/controllers/episodes_controller_test.rb`

Expected: All tests pass (or update tests if needed)

### Step 3: Commit

```bash
git add app/controllers/episodes_controller.rb
git commit -m "refactor: update EpisodesController to use CreateMarkdownEpisode"
```

---

## Task 11: Delete UploadAndEnqueueEpisode

**Files:**
- Delete: `hub/app/services/upload_and_enqueue_episode.rb`
- Delete: `hub/test/services/upload_and_enqueue_episode_test.rb`

### Step 1: Verify no remaining references

Run: `grep -r "UploadAndEnqueueEpisode" hub/app hub/test`

Expected: No matches (all references should be updated)

### Step 2: Delete the files

```bash
rm app/services/upload_and_enqueue_episode.rb
rm test/services/upload_and_enqueue_episode_test.rb
```

### Step 3: Run full test suite

Run: `bin/rails test`

Expected: All tests pass

### Step 4: Commit

```bash
git add -A
git commit -m "refactor: remove UploadAndEnqueueEpisode (replaced by SubmitEpisodeForProcessing)"
```

---

## Task 12: Delete EpisodeSubmissionService

**Files:**
- Delete: `hub/app/services/episode_submission_service.rb`
- Delete: `hub/test/services/episode_submission_service_test.rb`

### Step 1: Verify no remaining references

Run: `grep -r "EpisodeSubmissionService" hub/app hub/test`

Expected: No matches

### Step 2: Delete the files

```bash
rm app/services/episode_submission_service.rb
rm test/services/episode_submission_service_test.rb
```

### Step 3: Run full test suite

Run: `bin/rails test`

Expected: All tests pass

### Step 4: Commit

```bash
git add -A
git commit -m "refactor: remove EpisodeSubmissionService (replaced by CreateMarkdownEpisode)"
```

---

## Task 13: Final Verification

### Step 1: Run full test suite

Run: `bin/rails test`

Expected: All tests pass

### Step 2: Verify architecture

Confirm the new flow:

```
CreateUrlEpisode ─→ ProcessUrlEpisodeJob ─→ ProcessUrlEpisode ───────────────┐
                                                                              │
CreatePasteEpisode ─→ ProcessPasteEpisodeJob ─→ ProcessPasteEpisode ──────────┼─→ SubmitEpisodeForProcessing
                                                                              │         │
CreateMarkdownEpisode ─→ ProcessMarkdownEpisodeJob ─→ ProcessMarkdownEpisode ─┘         ├─→ BuildEpisodeWrapper
                                                                                        ├─→ UploadEpisodeContent
                                                                                        └─→ EnqueueEpisodeProcessing
```

### Step 3: Clean up any integration tests

Run: `bin/rails test test/integration/`

Fix any failing integration tests that reference old services.

### Step 4: Final commit if needed

```bash
git add -A
git commit -m "test: fix integration tests for new episode submission architecture"
```
