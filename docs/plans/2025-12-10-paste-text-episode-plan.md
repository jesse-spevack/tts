# Paste Text Episode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add "Paste Text" as a third episode creation option, extracting metadata via LLM.

**Architecture:** Mirrors URL episode flow - create episode with placeholder metadata, process asynchronously via background job. New `source_text` column stores pasted content. Reuses existing `LlmProcessor` for metadata extraction.

**Tech Stack:** Rails 8.1, Stimulus.js, SQLite, Mocktail for mocking

---

## Task 1: Database Migration

**Files:**
- Create: `hub/db/migrate/TIMESTAMP_add_source_text_to_episodes.rb`

**Step 1: Generate migration**

Run:
```bash
cd hub && bin/rails generate migration AddSourceTextToEpisodes source_text:text
```

**Step 2: Run migration**

Run:
```bash
cd hub && bin/rails db:migrate
```

Expected: Migration runs successfully, `source_text` column added to episodes table.

**Step 3: Verify schema updated**

Run:
```bash
cd hub && grep "source_text" db/schema.rb
```

Expected: Output shows `t.text "source_text"`

**Step 4: Commit**

```bash
git add hub/db/migrate/*_add_source_text_to_episodes.rb hub/db/schema.rb
git commit -m "Add source_text column to episodes"
```

---

## Task 2: Update Episode Model Enum

**Files:**
- Modify: `hub/app/models/episode.rb:11`

**Step 1: Write the failing test**

Create test file `hub/test/models/episode_source_type_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EpisodeSourceTypeTest < ActiveSupport::TestCase
  test "source_type includes paste" do
    assert_includes Episode.source_types.keys, "paste"
  end

  test "paste source_type has integer value 2" do
    assert_equal 2, Episode.source_types["paste"]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/models/episode_source_type_test.rb -v
```

Expected: FAIL - "paste" not in source_types

**Step 3: Update the enum**

In `hub/app/models/episode.rb`, change line 11 from:
```ruby
  enum :source_type, { file: 0, url: 1 }
```

To:
```ruby
  enum :source_type, { file: 0, url: 1, paste: 2 }
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd hub && bin/rails test test/models/episode_source_type_test.rb -v
```

Expected: PASS

**Step 5: Commit**

```bash
git add hub/app/models/episode.rb hub/test/models/episode_source_type_test.rb
git commit -m "Add paste to episode source_type enum"
```

---

## Task 3: CreatePasteEpisode Service

**Files:**
- Create: `hub/app/services/create_paste_episode.rb`
- Create: `hub/test/services/create_paste_episode_test.rb`

**Step 1: Write the failing tests**

Create `hub/test/services/create_paste_episode_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CreatePasteEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @valid_text = "A" * 150 # Above 100 char minimum
  end

  test "creates episode with processing status" do
    result = nil
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      result = CreatePasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end

    assert result.success?
    assert result.episode.persisted?
    assert_equal "processing", result.episode.status
    assert_equal "paste", result.episode.source_type
    assert_equal @valid_text, result.episode.source_text
  end

  test "creates episode with placeholder metadata" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text
    )

    assert_equal "Processing...", result.episode.title
    assert_equal "Processing...", result.episode.author
    assert_equal "Processing pasted text...", result.episode.description
  end

  test "fails on empty text" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: ""
    )

    assert result.failure?
    assert_equal "Text cannot be empty", result.error
    assert_nil result.episode
  end

  test "fails on nil text" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: nil
    )

    assert result.failure?
    assert_equal "Text cannot be empty", result.error
  end

  test "fails on text under 100 characters" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 99
    )

    assert result.failure?
    assert_equal "Text must be at least 100 characters", result.error
  end

  test "succeeds on text exactly 100 characters" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 100
    )

    assert result.success?
  end

  test "enqueues ProcessPasteEpisodeJob" do
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      CreatePasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd hub && bin/rails test test/services/create_paste_episode_test.rb -v
```

Expected: FAIL - uninitialized constant CreatePasteEpisode

**Step 3: Write minimal implementation**

Create `hub/app/services/create_paste_episode.rb`:

```ruby
# frozen_string_literal: true

class CreatePasteEpisode
  MINIMUM_LENGTH = 100

  def self.call(podcast:, user:, text:)
    new(podcast: podcast, user: user, text: text).call
  end

  def initialize(podcast:, user:, text:)
    @podcast = podcast
    @user = user
    @text = text
  end

  def call
    return Result.failure("Text cannot be empty") if text.blank?
    return Result.failure("Text must be at least #{MINIMUM_LENGTH} characters") if text.length < MINIMUM_LENGTH

    episode = create_episode
    ProcessPasteEpisodeJob.perform_later(episode.id)

    Rails.logger.info "event=paste_episode_created episode_id=#{episode.id} text_length=#{text.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :text

  def create_episode
    podcast.episodes.create!(
      user: user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: text,
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

**Step 4: Run tests (will still fail - job doesn't exist)**

Run:
```bash
cd hub && bin/rails test test/services/create_paste_episode_test.rb -v
```

Expected: FAIL - uninitialized constant ProcessPasteEpisodeJob

**Step 5: Create stub job to make tests pass**

Create `hub/app/jobs/process_paste_episode_job.rb`:

```ruby
class ProcessPasteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    # Implementation in next task
  end
end
```

**Step 6: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/services/create_paste_episode_test.rb -v
```

Expected: All 7 tests PASS

**Step 7: Commit**

```bash
git add hub/app/services/create_paste_episode.rb hub/test/services/create_paste_episode_test.rb hub/app/jobs/process_paste_episode_job.rb
git commit -m "Add CreatePasteEpisode service with validation"
```

---

## Task 4: ProcessPasteEpisode Service

**Files:**
- Create: `hub/app/services/process_paste_episode.rb`
- Create: `hub/test/services/process_paste_episode_test.rb`

**Step 1: Write the failing tests**

Create `hub/test/services/process_paste_episode_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessPasteEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @text = "This is the pasted article content that will be processed by the LLM to extract metadata and clean up for TTS conversion."
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: @text,
      status: :processing
    )

    Mocktail.replace(LlmProcessor)
    Mocktail.replace(UploadAndEnqueueEpisode)
  end

  test "processes text and updates episode metadata" do
    mock_llm_result = LlmProcessor::Result.success(
      title: "Extracted Title",
      author: "Extracted Author",
      description: "Extracted description.",
      content: "Cleaned content for TTS."
    )

    stubs { |m| LlmProcessor.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { true }

    ProcessPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Extracted Title", @episode.title
    assert_equal "Extracted Author", @episode.author
    assert_equal "Extracted description.", @episode.description
  end

  test "sets content_preview from LLM content" do
    long_content = "B" * 100 + " middle " + "X" * 100
    mock_llm_result = LlmProcessor::Result.success(
      title: "Title",
      author: "Author",
      description: "Description",
      content: long_content
    )

    stubs { |m| LlmProcessor.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { true }

    ProcessPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_not_nil @episode.content_preview
  end

  test "marks episode as failed when content too long for tier" do
    @episode.update!(source_text: "x" * 20_000)

    ProcessPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "too long"
  end

  test "marks episode as failed on LLM error" do
    mock_llm_result = LlmProcessor::Result.failure("LLM processing failed")

    stubs { |m| LlmProcessor.call(text: m.any, episode: m.any) }.with { mock_llm_result }

    ProcessPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "LLM processing failed", @episode.error_message
  end

  test "calls UploadAndEnqueueEpisode with cleaned content" do
    cleaned_content = "Cleaned content for TTS."
    mock_llm_result = LlmProcessor::Result.success(
      title: "Title",
      author: "Author",
      description: "Description",
      content: cleaned_content
    )

    stubs { |m| LlmProcessor.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { true }

    ProcessPasteEpisode.call(episode: @episode)

    verify { |m| UploadAndEnqueueEpisode.call(episode: @episode, content: cleaned_content) }
  end

  teardown do
    Mocktail.reset
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd hub && bin/rails test test/services/process_paste_episode_test.rb -v
```

Expected: FAIL - uninitialized constant ProcessPasteEpisode

**Step 3: Write minimal implementation**

Create `hub/app/services/process_paste_episode.rb`:

```ruby
# frozen_string_literal: true

class ProcessPasteEpisode
  include EpisodeLogging

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
    @user = episode.user
  end

  def call
    log_info "process_paste_episode_started", text_length: episode.source_text.length

    check_character_limit
    process_with_llm
    update_and_enqueue

    log_info "process_paste_episode_completed"
  rescue ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_paste_episode_error", error: e.class, message: e.message
    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def check_character_limit
    max_chars = MaxCharactersForUser.call(user: user)
    return unless max_chars && episode.source_text.length > max_chars

    log_warn "character_limit_exceeded", characters: episode.source_text.length, limit: max_chars, tier: user.tier
    raise ProcessingError, "This content is too long for your account tier"
  end

  def process_with_llm
    log_info "llm_processing_started", characters: episode.source_text.length

    @llm_result = LlmProcessor.call(text: episode.source_text, episode: episode)
    if @llm_result.failure?
      log_warn "llm_processing_failed", error: @llm_result.error
      raise ProcessingError, @llm_result.error
    end

    log_info "llm_processing_completed", title: @llm_result.title
  end

  def update_and_enqueue
    content = @llm_result.content

    Episode.transaction do
      episode.update!(
        title: @llm_result.title,
        author: @llm_result.author,
        description: @llm_result.description,
        content_preview: ContentPreview.generate(content)
      )

      log_info "episode_metadata_updated"

      UploadAndEnqueueEpisode.call(episode: episode, content: content)
    end
  end

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    log_warn "episode_marked_failed", error: error_message
  end

  class ProcessingError < StandardError; end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/services/process_paste_episode_test.rb -v
```

Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add hub/app/services/process_paste_episode.rb hub/test/services/process_paste_episode_test.rb
git commit -m "Add ProcessPasteEpisode service"
```

---

## Task 5: ProcessPasteEpisodeJob

**Files:**
- Modify: `hub/app/jobs/process_paste_episode_job.rb`
- Create: `hub/test/jobs/process_paste_episode_job_test.rb`

**Step 1: Write the failing test**

Create `hub/test/jobs/process_paste_episode_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessPasteEpisodeJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: "Test content for processing",
      status: :processing
    )

    Mocktail.replace(ProcessPasteEpisode)
  end

  test "calls ProcessPasteEpisode with episode" do
    stubs { |m| ProcessPasteEpisode.call(episode: m.any) }.with { true }

    ProcessPasteEpisodeJob.perform_now(@episode.id)

    verify { ProcessPasteEpisode.call(episode: @episode) }
  end

  teardown do
    Mocktail.reset
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd hub && bin/rails test test/jobs/process_paste_episode_job_test.rb -v
```

Expected: FAIL - verify fails because ProcessPasteEpisode.call was not called

**Step 3: Update the job implementation**

Replace `hub/app/jobs/process_paste_episode_job.rb` with:

```ruby
class ProcessPasteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    Rails.logger.info "event=process_paste_episode_job_started episode_id=#{episode_id}"

    episode = Episode.find(episode_id)
    ProcessPasteEpisode.call(episode: episode)

    Rails.logger.info "event=process_paste_episode_job_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=process_paste_episode_job_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd hub && bin/rails test test/jobs/process_paste_episode_job_test.rb -v
```

Expected: PASS

**Step 5: Commit**

```bash
git add hub/app/jobs/process_paste_episode_job.rb hub/test/jobs/process_paste_episode_job_test.rb
git commit -m "Implement ProcessPasteEpisodeJob"
```

---

## Task 6: Controller - create_from_paste

**Files:**
- Modify: `hub/app/controllers/episodes_controller.rb`
- Modify: `hub/test/controllers/episodes_controller_test.rb`

**Step 1: Write the failing tests**

Add to end of `hub/test/controllers/episodes_controller_test.rb`:

```ruby
  # Paste text episode creation tests

  test "create with text param creates paste episode and redirects" do
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      post episodes_url, params: { text: "A" * 150 }
    end

    assert_redirected_to episodes_path
    follow_redirect!
    assert_match(/Processing/, response.body)
  end

  test "create with text param fails with empty text" do
    post episodes_url, params: { text: "" }

    assert_response :unprocessable_entity
  end

  test "create with text param fails with text under 100 characters" do
    post episodes_url, params: { text: "A" * 99 }

    assert_response :unprocessable_entity
  end

  test "create with text param records episode usage for free tier" do
    free_user = users(:free_user)
    sign_in_as free_user

    assert_difference -> { EpisodeUsage.count }, 1 do
      post episodes_url, params: { text: "A" * 150 }
    end
  end

  test "redirects free tier user from text create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    post episodes_url, params: { text: "A" * 150 }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd hub && bin/rails test test/controllers/episodes_controller_test.rb -v -n /text/
```

Expected: FAIL - no route handles text param correctly

**Step 3: Update controller**

In `hub/app/controllers/episodes_controller.rb`, update the `create` method (around line 24) from:

```ruby
  def create
    if params[:url].present?
      create_from_url
    else
      create_from_markdown
    end
  end
```

To:

```ruby
  def create
    if params[:url].present?
      create_from_url
    elsif params[:text].present?
      create_from_paste
    else
      create_from_markdown
    end
  end
```

Then add the `create_from_paste` private method after `create_from_url` (around line 49):

```ruby
  def create_from_paste
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: Current.user,
      text: params[:text]
    )

    if result.success?
      RecordEpisodeUsage.call(user: Current.user)
      redirect_to episodes_path, notice: "Processing pasted text..."
    else
      flash.now[:alert] = result.error
      @episode = @podcast.episodes.build
      render :new, status: :unprocessable_entity
    end
  end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd hub && bin/rails test test/controllers/episodes_controller_test.rb -v -n /text/
```

Expected: All 5 tests PASS

**Step 5: Run all controller tests to ensure no regressions**

Run:
```bash
cd hub && bin/rails test test/controllers/episodes_controller_test.rb -v
```

Expected: All tests PASS

**Step 6: Commit**

```bash
git add hub/app/controllers/episodes_controller.rb hub/test/controllers/episodes_controller_test.rb
git commit -m "Add create_from_paste controller action"
```

---

## Task 7: Frontend - Add Paste Text Tab

**Files:**
- Modify: `hub/app/views/episodes/new.html.erb`

**Step 1: Update the view**

Replace the entire content of `hub/app/views/episodes/new.html.erb` with:

```erb
<div class="max-w-2xl mx-auto">
  <h1 class="text-2xl font-semibold mb-8">Create New Episode</h1>

  <%= render "shared/card", padding: "p-4 sm:p-8" do %>
    <div data-controller="tab-switch">
      <!-- Segmented Control -->
      <div class="flex bg-[var(--color-base)] rounded-lg p-1 mb-6">
        <button
          type="button"
          data-tab-switch-target="tab"
          data-tab="url"
          data-action="click->tab-switch#switch"
          class="flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors bg-[var(--color-surface0)] text-[var(--color-text)]"
        >
          From URL
        </button>
        <button
          type="button"
          data-tab-switch-target="tab"
          data-tab="paste"
          data-action="click->tab-switch#switch"
          class="flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors text-[var(--color-subtext)]"
        >
          Paste Text
        </button>
        <button
          type="button"
          data-tab-switch-target="tab"
          data-tab="file"
          data-action="click->tab-switch#switch"
          class="flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors text-[var(--color-subtext)]"
        >
          Upload File
        </button>
      </div>

      <!-- URL Form Panel -->
      <div data-tab-switch-target="panel" data-tab="url">
        <%= form_with url: episodes_path, local: true, class: "space-y-6" do |f| %>
          <div>
            <%= f.label :url, "Article URL", class: label_classes %>
            <%= f.url_field :url,
                class: input_classes,
                placeholder: "https://example.com/article",
                required: true %>
            <p class="mt-2 text-sm text-[var(--color-subtext)]">
              We'll extract the article content, title, and author automatically.
            </p>
          </div>

          <div class="flex flex-col sm:flex-row sm:items-center gap-4 pt-4">
            <%= f.submit "Create Episode", class: button_classes(type: :primary, full_width: false) + " sm:w-auto w-full" %>
            <%= link_to "Cancel", episodes_path, class: button_classes(type: :text) + " text-center" %>
          </div>
        <% end %>
      </div>

      <!-- Paste Text Form Panel -->
      <div data-tab-switch-target="panel" data-tab="paste" class="hidden">
        <%= form_with url: episodes_path, local: true, class: "space-y-6" do |f| %>
          <div>
            <%= f.label :text, "Article Text", class: label_classes %>
            <%= f.text_area :text,
                rows: 12,
                class: input_classes,
                placeholder: "Paste your article text here...",
                required: true %>
            <p class="mt-2 text-sm text-[var(--color-subtext)]">
              Paste article text. We'll extract the title and author automatically.
            </p>
          </div>

          <div class="flex flex-col sm:flex-row sm:items-center gap-4 pt-4">
            <%= f.submit "Create Episode", class: button_classes(type: :primary, full_width: false) + " sm:w-auto w-full" %>
            <%= link_to "Cancel", episodes_path, class: button_classes(type: :text) + " text-center" %>
          </div>
        <% end %>
      </div>

      <!-- File Form Panel -->
      <div data-tab-switch-target="panel" data-tab="file" class="hidden">
        <%= form_with model: @episode, url: episodes_path, local: true, multipart: true, class: "space-y-6" do |f| %>
          <% if @episode.errors.any? %>
            <div class="border border-[var(--color-red)] rounded-lg p-4 bg-[var(--color-red)]/10">
              <p class="text-[var(--color-red)] font-medium mb-2">Please fix the following errors:</p>
              <ul class="list-disc list-inside text-sm text-[var(--color-red)]">
                <% @episode.errors.full_messages.each do |message| %>
                  <li><%= message %></li>
                <% end %>
              </ul>
            </div>
          <% end %>

          <div>
            <%= f.label :title, class: label_classes %>
            <%= f.text_field :title,
                class: input_classes,
                placeholder: "My Awesome Episode" %>
          </div>

          <div>
            <%= f.label :author, class: label_classes %>
            <%= f.text_field :author,
                class: input_classes,
                placeholder: "Your Name" %>
          </div>

          <div>
            <%= f.label :description, class: label_classes %>
            <%= f.text_area :description,
                rows: 3,
                class: input_classes,
                placeholder: "A brief description of this episode..." %>
          </div>

          <div data-controller="file-upload">
            <%= f.label :content, "Markdown Content", class: label_classes %>
            <div
              data-file-upload-target="dropzone"
              data-action="click->file-upload#triggerInput dragover->file-upload#handleDragOver dragleave->file-upload#handleDragLeave drop->file-upload#handleDrop"
              class="border-2 border-dashed border-[var(--color-overlay0)] rounded-lg p-4 sm:p-8 text-center cursor-pointer hover:border-[var(--color-primary)] transition-colors"
            >
              <%= f.file_field :content,
                  accept: ".md,.markdown,.txt",
                  required: true,
                  data: { file_upload_target: "input", action: "change->file-upload#updateFilename" },
                  class: "hidden" %>
              <p class="text-[var(--color-subtext)] mb-2">Click to upload or drag and drop<br>(.md or .txt)</p>
              <p data-file-upload-target="filename" class="hidden text-sm font-medium text-[var(--color-primary)]"></p>
            </div>
          </div>

          <div class="flex flex-col sm:flex-row sm:items-center gap-4 pt-4">
            <%= f.submit "Create Episode", class: button_classes(type: :primary, full_width: false) + " sm:w-auto w-full" %>
            <%= link_to "Cancel", episodes_path, class: button_classes(type: :text) + " text-center" %>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

**Step 2: Verify manually in browser**

Run:
```bash
cd hub && bin/rails server
```

Visit http://localhost:3000/episodes/new and verify:
1. Three tabs appear: "From URL", "Paste Text", "Upload File"
2. Clicking each tab shows the correct panel
3. "From URL" is selected by default
4. "Paste Text" panel has a textarea

**Step 3: Commit**

```bash
git add hub/app/views/episodes/new.html.erb
git commit -m "Add Paste Text tab to episode creation form"
```

---

## Task 8: Integration Test

**Files:**
- Create: `hub/test/integration/paste_episode_flow_test.rb`

**Step 1: Write integration test**

Create `hub/test/integration/paste_episode_flow_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class PasteEpisodeFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(tier: :unlimited)
    sign_in_as(@user)

    Mocktail.replace(LlmProcessor)
    Mocktail.replace(UploadAndEnqueueEpisode)
  end

  test "full paste episode flow from form to completion" do
    text = "A" * 200

    # Submit the form
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      post episodes_url, params: { text: text }
    end

    assert_redirected_to episodes_path

    # Find the created episode
    episode = Episode.last
    assert_equal "paste", episode.source_type
    assert_equal "processing", episode.status
    assert_equal text, episode.source_text

    # Mock LLM response
    mock_llm_result = LlmProcessor::Result.success(
      title: "Generated Title",
      author: "Generated Author",
      description: "Generated description.",
      content: "Cleaned content."
    )
    stubs { |m| LlmProcessor.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { true }

    # Process the job
    perform_enqueued_jobs

    # Verify final state
    episode.reload
    assert_equal "Generated Title", episode.title
    assert_equal "Generated Author", episode.author
    assert_equal "Generated description.", episode.description
  end

  teardown do
    Mocktail.reset
  end
end
```

**Step 2: Run integration test**

Run:
```bash
cd hub && bin/rails test test/integration/paste_episode_flow_test.rb -v
```

Expected: PASS

**Step 3: Commit**

```bash
git add hub/test/integration/paste_episode_flow_test.rb
git commit -m "Add integration test for paste episode flow"
```

---

## Task 9: Final Verification

**Step 1: Run full test suite**

Run:
```bash
cd hub && bin/rails test
```

Expected: All tests PASS

**Step 2: Manual testing**

1. Start the server: `cd hub && bin/rails server`
2. Log in and navigate to /episodes/new
3. Click "Paste Text" tab
4. Paste some text (100+ characters)
5. Submit and verify episode shows "Processing..." status
6. Check Rails logs for processing events

**Step 3: Final commit if any cleanup needed**

```bash
git status
# If clean, no commit needed
```

---

## Summary of Files Created/Modified

**Created:**
- `hub/db/migrate/TIMESTAMP_add_source_text_to_episodes.rb`
- `hub/app/services/create_paste_episode.rb`
- `hub/app/services/process_paste_episode.rb`
- `hub/app/jobs/process_paste_episode_job.rb`
- `hub/test/models/episode_source_type_test.rb`
- `hub/test/services/create_paste_episode_test.rb`
- `hub/test/services/process_paste_episode_test.rb`
- `hub/test/jobs/process_paste_episode_job_test.rb`
- `hub/test/integration/paste_episode_flow_test.rb`

**Modified:**
- `hub/db/schema.rb` (auto-generated)
- `hub/app/models/episode.rb`
- `hub/app/controllers/episodes_controller.rb`
- `hub/app/views/episodes/new.html.erb`
- `hub/test/controllers/episodes_controller_test.rb`
