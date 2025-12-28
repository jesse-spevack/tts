# Validation Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move content validation from scattered services into the Episode model for data integrity.

**Architecture:** Add three validations to Episode model (presence, min length, tier limit) for paste/file source types. Simplify CreatePasteEpisode and CreateFileEpisode to delegate validation to model. Keep URL episode validation in ProcessUrlEpisode unchanged.

**Tech Stack:** Rails 8, ActiveRecord validations, Minitest

---

## Task 1: Add Locale Translation

**Files:**
- Modify: `config/locales/en.yml`

**Step 1: Add the activerecord attribute translation**

Edit `config/locales/en.yml` to add:

```yaml
en:
  hello: "Hello world"
  activerecord:
    attributes:
      episode:
        source_text: "Content"
```

**Step 2: Verify the locale file is valid**

Run: `bin/rails runner "puts I18n.t('activerecord.attributes.episode.source_text')"`

Expected: `Content`

**Step 3: Commit**

```bash
git add config/locales/en.yml
git commit -m "i18n: Add source_text attribute translation for Episode"
```

---

## Task 2: Add Episode Model Validations

**Files:**
- Modify: `app/models/episode.rb:19` (after existing validations)
- Test: `test/models/episode_test.rb`

**Step 1: Write failing tests for presence validation**

Add to `test/models/episode_test.rb`:

```ruby
test "paste episode requires source_text presence" do
  episode = Episode.new(
    podcast: podcasts(:one),
    user: users(:one),
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :paste,
    source_text: nil,
    status: :processing
  )

  assert_not episode.valid?
  assert_includes episode.errors[:source_text], "cannot be empty"
end

test "file episode requires source_text presence" do
  episode = Episode.new(
    podcast: podcasts(:one),
    user: users(:one),
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :file,
    source_text: "",
    status: :processing
  )

  assert_not episode.valid?
  assert_includes episode.errors[:source_text], "cannot be empty"
end

test "url episode does not require source_text" do
  episode = Episode.new(
    podcast: podcasts(:one),
    user: users(:one),
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :url,
    source_url: "https://example.com/article",
    source_text: nil,
    status: :processing
  )

  assert episode.valid?
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/episode_test.rb -n "/source_text presence/"`

Expected: 2 failures (paste and file tests fail, url test passes)

**Step 3: Write failing tests for minimum length validation**

Add to `test/models/episode_test.rb`:

```ruby
test "paste episode requires minimum 100 characters" do
  episode = Episode.new(
    podcast: podcasts(:one),
    user: users(:one),
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :paste,
    source_text: "A" * 99,
    status: :processing
  )

  assert_not episode.valid?
  assert episode.errors[:source_text].first.include?("at least 100 characters")
end

test "paste episode accepts exactly 100 characters" do
  episode = Episode.new(
    podcast: podcasts(:one),
    user: users(:one),
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :paste,
    source_text: "A" * 100,
    status: :processing
  )

  assert episode.valid?
end

test "file episode requires minimum 100 characters" do
  episode = Episode.new(
    podcast: podcasts(:one),
    user: users(:one),
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :file,
    source_text: "short",
    status: :processing
  )

  assert_not episode.valid?
  assert episode.errors[:source_text].first.include?("at least 100 characters")
end
```

**Step 4: Run tests to verify they fail**

Run: `bin/rails test test/models/episode_test.rb -n "/minimum/"`

Expected: 2 failures (min length tests fail, 100 char test passes vacuously)

**Step 5: Write failing tests for tier limit validation**

Add to `test/models/episode_test.rb`:

```ruby
test "paste episode validates tier character limit" do
  user = users(:free_user)
  max_chars = CalculatesMaxCharactersForUser.call(user: user)

  episode = Episode.new(
    podcast: podcasts(:one),
    user: user,
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :paste,
    source_text: "A" * (max_chars + 1),
    status: :processing
  )

  assert_not episode.valid?
  assert episode.errors[:source_text].first.include?("exceeds your plan's")
end

test "paste episode accepts content at tier limit" do
  user = users(:free_user)
  max_chars = CalculatesMaxCharactersForUser.call(user: user)

  episode = Episode.new(
    podcast: podcasts(:one),
    user: user,
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :paste,
    source_text: "A" * max_chars,
    status: :processing
  )

  assert episode.valid?
end

test "unlimited tier has no character limit" do
  user = users(:unlimited_user)

  episode = Episode.new(
    podcast: podcasts(:one),
    user: user,
    title: "Test",
    author: "Author",
    description: "Description",
    source_type: :paste,
    source_text: "A" * 100_000,
    status: :processing
  )

  assert episode.valid?
end
```

**Step 6: Run tests to verify they fail**

Run: `bin/rails test test/models/episode_test.rb -n "/tier/"`

Expected: 1 failure (tier limit test fails, others pass vacuously)

**Step 7: Implement the model validations**

Edit `app/models/episode.rb`. Add after line 19 (after `validates :duration_seconds`):

```ruby
validates :source_text, presence: { message: "cannot be empty" },
          if: -> { paste? || file? }

validates :source_text, length: {
            minimum: AppConfig::Content::MIN_LENGTH,
            message: "must be at least %{count} characters"
          },
          if: -> { paste? || file? },
          allow_blank: true

validate :content_within_tier_limit, on: :create,
         if: -> { source_text.present? }
```

Add to the private section (before `def broadcast_status_change`):

```ruby
def content_within_tier_limit
  max_chars = CalculatesMaxCharactersForUser.call(user: user)
  return unless max_chars

  if source_text.length > max_chars
    errors.add(:source_text,
      "exceeds your plan's #{max_chars.to_fs(:delimited)} character limit " \
      "(#{source_text.length.to_fs(:delimited)} characters)")
  end
end
```

**Step 8: Run all new model validation tests**

Run: `bin/rails test test/models/episode_test.rb`

Expected: All tests pass

**Step 9: Run full test suite to check for regressions**

Run: `bin/rails test`

Expected: All tests pass (service validations still in place as safety net)

**Step 10: Commit**

```bash
git add app/models/episode.rb test/models/episode_test.rb
git commit -m "feat: Add content validations to Episode model

- Presence validation for paste/file source types
- Minimum 100 character length validation
- Tier-based character limit validation on create
- URL episodes skip source_text validation (validated during processing)"
```

---

## Task 3: Simplify CreatePasteEpisode

**Files:**
- Modify: `app/services/create_paste_episode.rb`
- Modify: `test/services/create_paste_episode_test.rb`

**Step 1: Update the service to use model validation**

Replace the entire `call` method in `app/services/create_paste_episode.rb`:

```ruby
def call
  episode = podcast.episodes.create(
    user: user,
    title: "Processing...",
    author: "Processing...",
    description: "Processing pasted text...",
    source_type: :paste,
    source_text: text,
    status: :processing
  )

  return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

  ProcessPasteEpisodeJob.perform_later(episode.id)
  Rails.logger.info "event=paste_episode_created episode_id=#{episode.id} text_length=#{text.length}"

  Result.success(episode)
end
```

Remove these private methods (they're no longer needed):
- `exceeds_max_characters?`
- `max_characters_error`
- `create_episode`

The full service should now be:

```ruby
# frozen_string_literal: true

class CreatePasteEpisode
  def self.call(podcast:, user:, text:)
    new(podcast: podcast, user: user, text: text).call
  end

  def initialize(podcast:, user:, text:)
    @podcast = podcast
    @user = user
    @text = text
  end

  def call
    episode = podcast.episodes.create(
      user: user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: text,
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessPasteEpisodeJob.perform_later(episode.id)
    Rails.logger.info "event=paste_episode_created episode_id=#{episode.id} text_length=#{text.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :text
end
```

**Step 2: Update test assertions for new error messages**

In `test/services/create_paste_episode_test.rb`, update these tests:

Change the "fails on empty text" test:
```ruby
test "fails on empty text" do
  result = CreatePasteEpisode.call(
    podcast: @podcast,
    user: @user,
    text: ""
  )

  assert result.failure?
  assert_equal "Content cannot be empty", result.error
  assert_nil result.data
end
```

Change the "fails on nil text" test:
```ruby
test "fails on nil text" do
  result = CreatePasteEpisode.call(
    podcast: @podcast,
    user: @user,
    text: nil
  )

  assert result.failure?
  assert_equal "Content cannot be empty", result.error
end
```

Change the "fails on text under 100 characters" test:
```ruby
test "fails on text under 100 characters" do
  result = CreatePasteEpisode.call(
    podcast: @podcast,
    user: @user,
    text: "A" * 99
  )

  assert result.failure?
  assert_equal "Content must be at least 100 characters", result.error
end
```

Change the "fails when text exceeds max characters" test:
```ruby
test "fails when text exceeds max characters for user tier" do
  free_user = users(:free_user)
  max_chars = CalculatesMaxCharactersForUser.call(user: free_user)
  text_over_limit = "A" * (max_chars + 1)

  result = CreatePasteEpisode.call(
    podcast: @podcast,
    user: free_user,
    text: text_over_limit
  )

  assert result.failure?
  assert_includes result.error, "exceeds your plan's"
end
```

**Step 3: Run service tests**

Run: `bin/rails test test/services/create_paste_episode_test.rb`

Expected: All tests pass

**Step 4: Run full test suite**

Run: `bin/rails test`

Expected: All tests pass

**Step 5: Commit**

```bash
git add app/services/create_paste_episode.rb test/services/create_paste_episode_test.rb
git commit -m "refactor: Simplify CreatePasteEpisode to use model validation

Remove duplicate validation logic, delegate to Episode model.
Update test assertions for standardized error messages."
```

---

## Task 4: Simplify CreateFileEpisode

**Files:**
- Modify: `app/services/create_file_episode.rb`
- Modify: `test/services/create_file_episode_test.rb`

**Step 1: Update the service to use model validation**

Replace the entire content of `app/services/create_file_episode.rb`:

```ruby
# frozen_string_literal: true

class CreateFileEpisode
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
    plain_text = StripsMarkdown.call(content)

    episode = podcast.episodes.create(
      user: user,
      title: title,
      author: author,
      description: description,
      source_type: :file,
      source_text: content,
      content_preview: GeneratesContentPreview.call(plain_text),
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessFileEpisodeJob.perform_later(episode.id)
    Rails.logger.info "event=file_episode_created episode_id=#{episode.id} content_length=#{content.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :title, :author, :description, :content
end
```

**Step 2: Update test for new error message**

In `test/services/create_file_episode_test.rb`, update:

Change the "returns failure when content is blank" test:
```ruby
test "returns failure when content is blank" do
  result = CreateFileEpisode.call(
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
```

Change the "returns failure when content exceeds max characters" test:
```ruby
test "returns failure when content exceeds max characters" do
  @user.update!(tier: :free)
  max_chars = CalculatesMaxCharactersForUser.call(user: @user)
  long_content = "a" * (max_chars + 1)

  result = CreateFileEpisode.call(
    podcast: @podcast,
    user: @user,
    title: "Test",
    author: "Author",
    description: "Desc",
    content: long_content
  )

  assert result.failure?
  assert_includes result.error, "exceeds your plan's"
end
```

**Step 3: Add test for new minimum length validation (bug fix)**

Add to `test/services/create_file_episode_test.rb`:

```ruby
test "returns failure when content is under 100 characters" do
  result = CreateFileEpisode.call(
    podcast: @podcast,
    user: @user,
    title: "Test",
    author: "Author",
    description: "Desc",
    content: "short"
  )

  assert result.failure?
  assert_equal "Content must be at least 100 characters", result.error
end
```

**Step 4: Update existing test that uses short content**

The test "creates episode with markdown source type" uses short content. Update it:

```ruby
test "creates episode with markdown source type" do
  long_content = "# Markdown content\n\n" + ("This is test content. " * 10)

  result = CreateFileEpisode.call(
    podcast: @podcast,
    user: @user,
    title: "Test Title",
    author: "Test Author",
    description: "Test description",
    content: long_content
  )

  assert result.success?
  assert_equal :file, result.data.source_type.to_sym
  assert_equal "Test Title", result.data.title
  assert_equal "Test Author", result.data.author
  assert_equal "Test description", result.data.description
  assert_equal long_content, result.data.source_text
end
```

Update other tests that use short content:

```ruby
test "sets episode status to processing" do
  long_content = "A" * 150

  result = CreateFileEpisode.call(
    podcast: @podcast,
    user: @user,
    title: "Test",
    author: "Author",
    description: "Desc",
    content: long_content
  )

  assert_equal "processing", result.data.status
end

test "enqueues ProcessFileEpisodeJob" do
  long_content = "A" * 150

  assert_enqueued_with(job: ProcessFileEpisodeJob) do
    CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )
  end
end

test "sets content preview" do
  long_content = "# Header\n\n" + ("Some markdown content here. " * 10)

  result = CreateFileEpisode.call(
    podcast: @podcast,
    user: @user,
    title: "Test",
    author: "Author",
    description: "Desc",
    content: long_content
  )

  assert result.data.content_preview.present?
end
```

**Step 5: Run service tests**

Run: `bin/rails test test/services/create_file_episode_test.rb`

Expected: All tests pass

**Step 6: Run full test suite**

Run: `bin/rails test`

Expected: All tests pass

**Step 7: Commit**

```bash
git add app/services/create_file_episode.rb test/services/create_file_episode_test.rb
git commit -m "refactor: Simplify CreateFileEpisode to use model validation

Remove duplicate validation logic, delegate to Episode model.
Also enforces minimum 100 char length (bug fix - was missing before).
Update test assertions for standardized error messages."
```

---

## Task 5: Standardize ProcessUrlEpisode Error Message

**Files:**
- Modify: `app/services/process_url_episode.rb:65-71`

**Step 1: Update the error message format**

In `app/services/process_url_episode.rb`, replace the `check_character_limit` method:

```ruby
def check_character_limit
  max_chars = CalculatesMaxCharactersForUser.call(user: user)
  return unless max_chars && @extract_result.data.character_count > max_chars

  log_warn "character_limit_exceeded", characters: @extract_result.data.character_count, limit: max_chars, tier: user.tier

  raise ProcessingError,
    "Content exceeds your plan's #{max_chars.to_fs(:delimited)} character limit " \
    "(#{@extract_result.data.character_count.to_fs(:delimited)} characters)"
end
```

**Step 2: Run related tests**

Run: `bin/rails test test/services/process_url_episode_test.rb`

Expected: All tests pass (error message tests may need updating if they check exact text)

**Step 3: Run full test suite**

Run: `bin/rails test`

Expected: All tests pass

**Step 4: Commit**

```bash
git add app/services/process_url_episode.rb
git commit -m "refactor: Standardize ProcessUrlEpisode error message format

Align with Episode model validation message style for consistency."
```

---

## Task 6: Final Cleanup and Verification

**Files:**
- None (verification only)

**Step 1: Run full test suite**

Run: `bin/rails test`

Expected: All tests pass

**Step 2: Run RuboCop**

Run: `bin/rubocop app/models/episode.rb app/services/create_paste_episode.rb app/services/create_file_episode.rb app/services/process_url_episode.rb`

Expected: No offenses (or fix any that appear)

**Step 3: Manually verify error messages in browser (optional)**

1. Start server: `bin/rails server`
2. Go to new episode page
3. Try pasting empty text → Should see "Content cannot be empty"
4. Try pasting < 100 chars → Should see "Content must be at least 100 characters"
5. As free user, paste > 15,000 chars → Should see tier limit message

**Step 4: Create final commit if any cleanup was needed**

```bash
git add -A
git commit -m "chore: Final cleanup for validation consolidation"
```

---

## Summary of Changes

| File | Lines Before | Lines After | Change |
|------|-------------|-------------|--------|
| `app/models/episode.rb` | 55 | ~75 | +20 (validations) |
| `app/services/create_paste_episode.rb` | 52 | 32 | -20 |
| `app/services/create_file_episode.rb` | 57 | 37 | -20 |
| `app/services/process_url_episode.rb` | 111 | 112 | +1 (message format) |
| `config/locales/en.yml` | 31 | 36 | +5 |
| `test/models/episode_test.rb` | 107 | ~160 | +53 (validation tests) |

**Net code change:** ~+39 lines (mostly tests), but validation logic is now in one place instead of four.
