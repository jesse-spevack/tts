# Content Preview Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show truncated first/last sentence preview in episode list to confirm full article was processed.

**Architecture:** Add `content_preview` column to episodes table, compute preview when content is submitted (both file upload and URL paths), display in episode card.

**Tech Stack:** Rails 8, SQLite, ERB views, Tailwind CSS

---

## Task 1: Add content_preview column to episodes

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_content_preview_to_episodes.rb`

**Step 1: Generate migration**

Run:
```bash
bin/rails generate migration AddContentPreviewToEpisodes content_preview:text
```

**Step 2: Run migration**

Run:
```bash
bin/rails db:migrate
```

Expected: Migration completes, `content_preview` column added to episodes table.

**Step 3: Verify schema**

Run:
```bash
grep content_preview db/schema.rb
```

Expected: `t.text "content_preview"` appears in episodes table.

**Step 4: Commit**

```bash
git add db/migrate/*_add_content_preview_to_episodes.rb db/schema.rb
git commit -m "Add content_preview column to episodes"
```

---

## Task 2: Create ContentPreview service

**Files:**
- Create: `app/services/content_preview.rb`
- Create: `test/services/content_preview_test.rb`

**Step 1: Write the failing test**

Create `test/services/content_preview_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ContentPreviewTest < ActiveSupport::TestCase
  test "returns full text when shorter than double preview length" do
    short_text = "Hello world!"
    result = ContentPreview.generate(short_text)
    assert_equal "Hello world!", result
  end

  test "truncates long text showing start and end" do
    # Create text that's definitely long enough to truncate
    long_text = "A" * 60 + " middle content here " + "Z" * 60
    result = ContentPreview.generate(long_text)

    assert result.start_with?("A" * 57 + "...")
    assert result.end_with?("..." + "Z" * 57)
    assert result.include?("\" \"")
  end

  test "preserves exactly 60 characters on each side" do
    start_part = "X" * 60
    end_part = "Y" * 60
    long_text = start_part + ("M" * 100) + end_part

    result = ContentPreview.generate(long_text)

    # Format: "XXX..." "...YYY"
    # Start: 57 chars + "..." = 60 display chars
    # End: "..." + 57 chars = 60 display chars
    assert_includes result, "X" * 57 + "..."
    assert_includes result, "..." + "Y" * 57
  end

  test "handles nil input" do
    result = ContentPreview.generate(nil)
    assert_nil result
  end

  test "handles empty string" do
    result = ContentPreview.generate("")
    assert_equal "", result
  end

  test "strips whitespace from start and end" do
    text_with_whitespace = "  Hello world  "
    result = ContentPreview.generate(text_with_whitespace)
    assert_equal "Hello world", result
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/services/content_preview_test.rb
```

Expected: FAIL with `NameError: uninitialized constant ContentPreview`

**Step 3: Write minimal implementation**

Create `app/services/content_preview.rb`:

```ruby
# frozen_string_literal: true

class ContentPreview
  PREVIEW_LENGTH = 60
  ELLIPSIS = "..."

  def self.generate(text)
    return nil if text.nil?

    text = text.strip
    return text if text.empty?

    # If text is short enough, return as-is
    # Need room for: start(57) + ellipsis(3) + space + quote + space + quote + ellipsis(3) + end(57)
    min_truncation_length = (PREVIEW_LENGTH * 2) + 10
    return text if text.length <= min_truncation_length

    start_chars = PREVIEW_LENGTH - ELLIPSIS.length
    end_chars = PREVIEW_LENGTH - ELLIPSIS.length

    start_part = text[0, start_chars].strip + ELLIPSIS
    end_part = ELLIPSIS + text[-end_chars, end_chars].strip

    "#{start_part}\" \"#{end_part}"
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/services/content_preview_test.rb
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/services/content_preview.rb test/services/content_preview_test.rb
git commit -m "Add ContentPreview service"
```

---

## Task 3: Integrate preview into file upload path

**Files:**
- Modify: `app/services/episode_submission_service.rb`
- Modify: `test/services/episode_submission_service_test.rb`

**Step 1: Write the failing test**

Add to `test/services/episode_submission_service_test.rb`:

```ruby
test "sets content_preview on episode" do
  long_content = "A" * 100 + " middle " + "Z" * 100
  uploaded_file = StringIO.new(long_content)
  uploaded_file.define_singleton_method(:read) { long_content }
  uploaded_file.define_singleton_method(:rewind) { }

  UploadAndEnqueueEpisode.stub(:call, nil) do
    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: { title: "Test", author: "Author", description: "Desc" },
      uploaded_file: uploaded_file
    )

    assert result.success?
    assert_not_nil result.episode.content_preview
    assert result.episode.content_preview.start_with?("A" * 57 + "...")
    assert result.episode.content_preview.end_with?("..." + "Z" * 57)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/services/episode_submission_service_test.rb -n test_sets_content_preview_on_episode
```

Expected: FAIL - assertion fails because `content_preview` is nil.

**Step 3: Modify EpisodeSubmissionService to set preview**

In `app/services/episode_submission_service.rb`, modify the `call` method. Change lines 29-35 from:

```ruby
    episode = build_episode
    return Result.failure(episode) unless episode.save

    Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{user.id} title=\"#{episode.title}\""

    content = uploaded_file.read
    UploadAndEnqueueEpisode.call(episode: episode, content: content)
```

To:

```ruby
    content = uploaded_file.read

    episode = build_episode
    episode.content_preview = ContentPreview.generate(content)
    return Result.failure(episode) unless episode.save

    Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{user.id} title=\"#{episode.title}\""

    UploadAndEnqueueEpisode.call(episode: episode, content: content)
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/services/episode_submission_service_test.rb
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/services/episode_submission_service.rb test/services/episode_submission_service_test.rb
git commit -m "Set content_preview on file upload"
```

---

## Task 4: Integrate preview into URL path

**Files:**
- Modify: `app/services/process_url_episode.rb`
- Modify: `test/services/process_url_episode_test.rb`

**Step 1: Write the failing test**

Add to `test/services/process_url_episode_test.rb`:

```ruby
test "sets content_preview on episode from LLM content" do
  long_content = "B" * 100 + " middle " + "X" * 100

  UrlFetcher.stub(:call, UrlFetcher::Result.success("<html><body>test</body></html>")) do
    ArticleExtractor.stub(:call, ArticleExtractor::Result.success("extracted", title: "Title", author: "Author")) do
      llm_result = LlmProcessor::Result.success(
        title: "LLM Title",
        author: "LLM Author",
        description: "LLM Desc",
        content: long_content
      )
      LlmProcessor.stub(:call, llm_result) do
        UploadAndEnqueueEpisode.stub(:call, nil) do
          ProcessUrlEpisode.call(episode: @episode, user: @user)
        end
      end
    end
  end

  @episode.reload
  assert_not_nil @episode.content_preview
  assert @episode.content_preview.start_with?("B" * 57 + "...")
  assert @episode.content_preview.end_with?("..." + "X" * 57)
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/services/process_url_episode_test.rb -n test_sets_content_preview_on_episode_from_LLM_content
```

Expected: FAIL - assertion fails because `content_preview` is nil.

**Step 3: Modify ProcessUrlEpisode to set preview**

In `app/services/process_url_episode.rb`, find the `submit_to_generator` method (around line 93-96). Change:

```ruby
def submit_to_generator
  UploadAndEnqueueEpisode.call(episode: episode, content: @llm_result.content)
end
```

To:

```ruby
def submit_to_generator
  content = @llm_result.content
  episode.update!(content_preview: ContentPreview.generate(content))
  UploadAndEnqueueEpisode.call(episode: episode, content: content)
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/services/process_url_episode_test.rb
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/services/process_url_episode.rb test/services/process_url_episode_test.rb
git commit -m "Set content_preview on URL episode"
```

---

## Task 5: Display preview in episode card

**Files:**
- Modify: `app/views/episodes/_episode_card.html.erb`

**Step 1: Modify the episode card partial**

In `app/views/episodes/_episode_card.html.erb`, add the preview display after the author/date line. Change:

```erb
    <div class="flex justify-between items-center text-sm text-[var(--color-subtext)]">
      <span>by <%= episode.author %></span>
      <span><%= episode.created_at.strftime("%b %d, %Y") %></span>
    </div>
```

To:

```erb
    <div class="flex justify-between items-center text-sm text-[var(--color-subtext)]">
      <span>by <%= episode.author %></span>
      <span><%= episode.created_at.strftime("%b %d, %Y") %></span>
    </div>
    <% if episode.content_preview.present? %>
      <p class="mt-2 text-xs text-[var(--color-subtext)] font-mono truncate">
        <%= episode.content_preview %>
      </p>
    <% end %>
```

**Step 2: Verify manually**

Run:
```bash
bin/rails server
```

Visit the episodes page and verify the preview appears for episodes that have `content_preview` set.

**Step 3: Commit**

```bash
git add app/views/episodes/_episode_card.html.erb
git commit -m "Display content_preview in episode card"
```

---

## Task 6: Run full test suite

**Step 1: Run all tests**

Run:
```bash
bin/rails test
```

Expected: All tests pass.

**Step 2: Run rubocop**

Run:
```bash
bundle exec rubocop
```

Expected: No offenses or only pre-existing ones.

---

## Summary

After completing all tasks:

1. Episodes table has `content_preview` text column
2. `ContentPreview` service generates `"Start..." "...End"` format with 60 chars each side
3. File uploads set preview from uploaded content
4. URL episodes set preview from LLM-processed content
5. Episode card displays preview in monospace font

The preview appears immediately when the episode is created (before processing completes), giving instant verification that the full content was received.
