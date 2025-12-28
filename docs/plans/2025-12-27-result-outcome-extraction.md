# Result and Outcome Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract duplicated Result classes from 7 services into shared `Result` and `Outcome` base classes.

**Architecture:** Two shared classes: `Result` for operations returning data (6 services), `Outcome` for permission checks with user-facing messages (1 service). Both live in `app/models/`. Services define their own data structs for multi-value returns.

**Tech Stack:** Ruby, Rails, Minitest

---

## Task 1: Create Result Class

**Files:**
- Create: `app/models/result.rb`
- Create: `test/models/result_test.rb`

**Step 1: Write the failing test**

Create `test/models/result_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ResultTest < ActiveSupport::TestCase
  test "success creates successful result with data" do
    result = Result.success("hello")

    assert result.success?
    refute result.failure?
    assert_equal "hello", result.data
    assert_nil result.error
  end

  test "success works with nil data" do
    result = Result.success(nil)

    assert result.success?
    assert_nil result.data
  end

  test "failure creates failed result with error" do
    result = Result.failure("boom")

    refute result.success?
    assert result.failure?
    assert_nil result.data
    assert_equal "boom", result.error
  end

  test "results are frozen" do
    result = Result.success("data")

    assert result.frozen?
  end

  test "success works with struct data" do
    TestData = Struct.new(:name, :value, keyword_init: true)
    data = TestData.new(name: "test", value: 42)

    result = Result.success(data)

    assert result.success?
    assert_equal "test", result.data.name
    assert_equal 42, result.data.value
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/result_test.rb`

Expected: Error - `NameError: uninitialized constant Result`

**Step 3: Write minimal implementation**

Create `app/models/result.rb`:

```ruby
# frozen_string_literal: true

class Result
  attr_reader :data, :error

  def initialize(success:, data:, error:)
    @success = success
    @data = data
    @error = error
    freeze
  end

  def self.success(data)
    new(success: true, data: data, error: nil)
  end

  def self.failure(error)
    new(success: false, data: nil, error: error)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/result_test.rb`

Expected: All 5 tests pass

**Step 5: Commit**

```bash
git add app/models/result.rb test/models/result_test.rb
git commit -m "feat: Add shared Result class for service return values"
```

---

## Task 2: Create Outcome Class

**Files:**
- Create: `app/models/outcome.rb`
- Create: `test/models/outcome_test.rb`

**Step 1: Write the failing test**

Create `test/models/outcome_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class OutcomeTest < ActiveSupport::TestCase
  test "success creates successful outcome with message" do
    outcome = Outcome.success("It worked")

    assert outcome.success?
    refute outcome.failure?
    assert_equal "It worked", outcome.message
    assert_nil outcome.error
    assert_nil outcome.data
  end

  test "success works with nil message" do
    outcome = Outcome.success

    assert outcome.success?
    assert_nil outcome.message
  end

  test "success accepts optional data kwargs" do
    outcome = Outcome.success("Allowed", remaining: 5)

    assert outcome.success?
    assert_equal "Allowed", outcome.message
    assert_equal({ remaining: 5 }, outcome.data)
  end

  test "failure creates failed outcome with message" do
    outcome = Outcome.failure("Not allowed")

    refute outcome.success?
    assert outcome.failure?
    assert_equal "Not allowed", outcome.message
    assert_nil outcome.data
  end

  test "failure accepts optional error" do
    error = StandardError.new("details")
    outcome = Outcome.failure("Failed", error: error)

    assert outcome.failure?
    assert_equal "Failed", outcome.message
    assert_equal error, outcome.error
  end

  test "outcomes are frozen" do
    outcome = Outcome.success("test")

    assert outcome.frozen?
  end

  test "flash_type returns notice for success" do
    outcome = Outcome.success("Yay")

    assert_equal :notice, outcome.flash_type
  end

  test "flash_type returns alert for failure" do
    outcome = Outcome.failure("Nope")

    assert_equal :alert, outcome.flash_type
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/outcome_test.rb`

Expected: Error - `NameError: uninitialized constant Outcome`

**Step 3: Write minimal implementation**

Create `app/models/outcome.rb`:

```ruby
# frozen_string_literal: true

class Outcome
  attr_reader :message, :error, :data

  def initialize(success:, message:, error:, data:)
    @success = success
    @message = message
    @error = error
    @data = data
    freeze
  end

  def self.success(message = nil, **data)
    new(success: true, message: message, error: nil, data: data.empty? ? nil : data)
  end

  def self.failure(message, error: nil)
    new(success: false, message: message, error: error, data: nil)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def flash_type
    success? ? :notice : :alert
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/outcome_test.rb`

Expected: All 8 tests pass

**Step 5: Commit**

```bash
git add app/models/outcome.rb test/models/outcome_test.rb
git commit -m "feat: Add shared Outcome class for permission checks"
```

---

## Task 3: Migrate CreateUrlEpisode to Shared Result

**Files:**
- Modify: `app/services/create_url_episode.rb` (lines 45-68 - remove Result class)

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/create_url_episode_test.rb`

Expected: All 5 tests pass

**Step 2: Remove inline Result class**

In `app/services/create_url_episode.rb`, delete lines 45-68 (the entire `class Result ... end` block).

The file should end at line 44 (the closing `end` for `CreateUrlEpisode`).

**Step 3: Update call site to use shared Result**

In `app/services/create_url_episode.rb`, the `call` method already uses `Result.success(episode)` and `Result.failure("Invalid URL")`. These now reference the shared `Result` class. However, we need to change how data is accessed.

Current test uses `result.episode`. With shared Result, it will be `result.data`.

**Step 4: Run tests to check for failures**

Run: `bin/rails test test/services/create_url_episode_test.rb`

Expected: Tests FAIL because they access `result.episode` instead of `result.data`

**Step 5: Update tests to use result.data**

In `test/services/create_url_episode_test.rb`, replace all occurrences:
- `result.episode` → `result.data`

Lines to change:
- Line 24: `assert result.data.persisted?`
- Line 25: `assert_equal "processing", result.data.status`
- Line 26: `assert_equal "url", result.data.source_type`
- Line 27: `assert_equal "https://example.com/article", result.data.source_url`
- Line 37: `assert_equal "Processing...", result.data.title`
- Line 38: `assert_equal "Processing...", result.data.author`
- Line 39: `assert_equal "Processing article from URL...", result.data.description`
- Line 51: `assert_nil result.data`

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/services/create_url_episode_test.rb`

Expected: All 5 tests pass

**Step 7: Commit**

```bash
git add app/services/create_url_episode.rb test/services/create_url_episode_test.rb
git commit -m "refactor: Migrate CreateUrlEpisode to shared Result class"
```

---

## Task 4: Migrate CreatePasteEpisode to Shared Result

**Files:**
- Modify: `app/services/create_paste_episode.rb` (lines 55-78 - remove Result class)
- Modify: `test/services/create_paste_episode_test.rb`

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/create_paste_episode_test.rb`

Expected: All tests pass

**Step 2: Remove inline Result class**

In `app/services/create_paste_episode.rb`, delete lines 55-78 (the entire `class Result ... end` block).

**Step 3: Run tests to check for failures**

Run: `bin/rails test test/services/create_paste_episode_test.rb`

Expected: Tests FAIL because they access `result.episode` instead of `result.data`

**Step 4: Update tests to use result.data**

In `test/services/create_paste_episode_test.rb`, replace all occurrences of `result.episode` with `result.data`.

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/services/create_paste_episode_test.rb`

Expected: All tests pass

**Step 6: Commit**

```bash
git add app/services/create_paste_episode.rb test/services/create_paste_episode_test.rb
git commit -m "refactor: Migrate CreatePasteEpisode to shared Result class"
```

---

## Task 5: Migrate CreateFileEpisode to Shared Result

**Files:**
- Modify: `app/services/create_file_episode.rb` (lines 58-81 - remove Result class)
- Modify: `test/services/create_file_episode_test.rb`

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/create_file_episode_test.rb`

Expected: All tests pass

**Step 2: Remove inline Result class**

In `app/services/create_file_episode.rb`, delete lines 58-81 (the entire `class Result ... end` block).

**Step 3: Run tests to check for failures**

Run: `bin/rails test test/services/create_file_episode_test.rb`

Expected: Tests FAIL because they access `result.episode` instead of `result.data`

**Step 4: Update tests to use result.data**

In `test/services/create_file_episode_test.rb`, replace all occurrences of `result.episode` with `result.data`.

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/services/create_file_episode_test.rb`

Expected: All tests pass

**Step 6: Commit**

```bash
git add app/services/create_file_episode.rb test/services/create_file_episode_test.rb
git commit -m "refactor: Migrate CreateFileEpisode to shared Result class"
```

---

## Task 6: Migrate FetchesUrl to Shared Result

**Files:**
- Modify: `app/services/fetches_url.rb` (lines 131-154 - remove Result class)
- Modify: `app/services/process_url_episode.rb` (line 49 - change `.html` to `.data`)
- Modify: `test/services/fetches_url_test.rb`

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/fetches_url_test.rb`

Expected: All tests pass

**Step 2: Remove inline Result class**

In `app/services/fetches_url.rb`, delete lines 131-154 (the entire `class Result ... end` block).

**Step 3: Run tests to check for failures**

Run: `bin/rails test test/services/fetches_url_test.rb`

Expected: Tests FAIL because they access `result.html` instead of `result.data`

**Step 4: Update tests to use result.data**

In `test/services/fetches_url_test.rb`, replace all occurrences of `result.html` with `result.data`.

**Step 5: Update ProcessUrlEpisode call site**

In `app/services/process_url_episode.rb`:
- Line 49: change `@fetch_result.html.bytesize` to `@fetch_result.data.bytesize`
- Line 55: change `@fetch_result.html` to `@fetch_result.data`

**Step 6: Run all affected tests**

Run: `bin/rails test test/services/fetches_url_test.rb test/services/process_url_episode_test.rb`

Expected: All tests pass

**Step 7: Commit**

```bash
git add app/services/fetches_url.rb app/services/process_url_episode.rb test/services/fetches_url_test.rb
git commit -m "refactor: Migrate FetchesUrl to shared Result class"
```

---

## Task 7: Migrate ExtractsArticle to Shared Result

**Files:**
- Modify: `app/services/extracts_article.rb` (lines 70-99 - refactor Result class)
- Modify: `app/services/process_url_episode.rb` (lines 62, 67, 69, 75, 77, 92, 93)
- Modify: `test/services/extracts_article_test.rb`

This service needs a data struct because it returns multiple values: `text`, `title`, `author`.

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/extracts_article_test.rb`

Expected: All tests pass

**Step 2: Add data struct and update Result usage**

Replace the inline Result class (lines 70-99) in `app/services/extracts_article.rb` with a data struct:

```ruby
  ArticleData = Struct.new(:text, :title, :author, keyword_init: true) do
    def character_count
      text&.length || 0
    end
  end
```

**Step 3: Update the call method return**

In `app/services/extracts_article.rb`, change line 34:

From:
```ruby
Result.success(text, title: extract_title(doc), author: extract_author(doc))
```

To:
```ruby
Result.success(ArticleData.new(text: text, title: extract_title(doc), author: extract_author(doc)))
```

**Step 4: Update tests to use result.data**

In `test/services/extracts_article_test.rb`, replace:
- `result.text` → `result.data.text`
- `result.title` → `result.data.title`
- `result.author` → `result.data.author`
- `result.character_count` → `result.data.character_count`

**Step 5: Update ProcessUrlEpisode call sites**

In `app/services/process_url_episode.rb`:
- Line 62: `@extract_result.character_count` → `@extract_result.data.character_count`
- Line 67: `@extract_result.character_count` → `@extract_result.data.character_count`
- Line 69: `@extract_result.character_count` → `@extract_result.data.character_count`
- Line 75: `@extract_result.character_count` → `@extract_result.data.character_count`
- Line 77: `@extract_result.text` → `@extract_result.data.text`
- Line 92: `@extract_result.title` → `@extract_result.data.title`
- Line 93: `@extract_result.author` → `@extract_result.data.author`

**Step 6: Run all affected tests**

Run: `bin/rails test test/services/extracts_article_test.rb test/services/process_url_episode_test.rb`

Expected: All tests pass

**Step 7: Commit**

```bash
git add app/services/extracts_article.rb app/services/process_url_episode.rb test/services/extracts_article_test.rb
git commit -m "refactor: Migrate ExtractsArticle to shared Result with ArticleData struct"
```

---

## Task 8: Migrate ProcessesWithLlm to Shared Result

**Files:**
- Modify: `app/services/processes_with_llm.rb` (lines 101-127 - refactor Result class)
- Modify: `app/services/process_url_episode.rb` (lines 84, 88, 92, 93, 94)
- Modify: `app/services/process_paste_episode.rb` (lines 51, 55, 59, 60, 61)
- Modify: `test/services/processes_with_llm_test.rb`

This service needs a data struct because it returns multiple values: `title`, `author`, `description`, `content`.

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/processes_with_llm_test.rb`

Expected: All tests pass

**Step 2: Add data struct**

Add at the top of the class in `app/services/processes_with_llm.rb` (after line 7):

```ruby
  LlmData = Struct.new(:title, :author, :description, :content, keyword_init: true)
```

**Step 3: Update the call method return**

In `app/services/processes_with_llm.rb`, change line 37:

From:
```ruby
Result.success(**validated)
```

To:
```ruby
Result.success(LlmData.new(**validated))
```

**Step 4: Delete the inline Result class**

Delete lines 101-127 (the entire `class Result ... end` block).

**Step 5: Update tests to use result.data**

In `test/services/processes_with_llm_test.rb`, replace:
- `result.title` → `result.data.title`
- `result.author` → `result.data.author`
- `result.description` → `result.data.description`
- `result.content` → `result.data.content`

**Step 6: Update ProcessUrlEpisode call sites**

In `app/services/process_url_episode.rb`:
- Line 84: `@llm_result.title` → `@llm_result.data.title`
- Line 88: `@llm_result.content` → `@llm_result.data.content`
- Line 92: `@llm_result.title` → `@llm_result.data.title`
- Line 93: `@llm_result.author` → `@llm_result.data.author`
- Line 94: `@llm_result.description` → `@llm_result.data.description`

**Step 7: Update ProcessPasteEpisode call sites**

In `app/services/process_paste_episode.rb`:
- Line 51: `@llm_result.title` → `@llm_result.data.title`
- Line 55: `@llm_result.content` → `@llm_result.data.content`
- Line 59: `@llm_result.title` → `@llm_result.data.title`
- Line 60: `@llm_result.author` → `@llm_result.data.author`
- Line 61: `@llm_result.description` → `@llm_result.data.description`

**Step 8: Run all affected tests**

Run: `bin/rails test test/services/processes_with_llm_test.rb test/services/process_url_episode_test.rb test/services/process_paste_episode_test.rb`

Expected: All tests pass

**Step 9: Commit**

```bash
git add app/services/processes_with_llm.rb app/services/process_url_episode.rb app/services/process_paste_episode.rb test/services/processes_with_llm_test.rb
git commit -m "refactor: Migrate ProcessesWithLlm to shared Result with LlmData struct"
```

---

## Task 9: Migrate ChecksEpisodeCreationPermission to Shared Outcome

**Files:**
- Modify: `app/services/checks_episode_creation_permission.rb` (lines 33-56 - remove Result class)
- Modify: `app/controllers/episodes_controller.rb` (line 91)
- Modify: `test/services/checks_episode_creation_permission_test.rb`

This service uses `allowed?`/`denied?` semantics. We migrate to `Outcome` with `success?`/`failure?`.

**Step 1: Run existing tests to verify they pass**

Run: `bin/rails test test/services/checks_episode_creation_permission_test.rb`

Expected: All 7 tests pass

**Step 2: Update the call method to use Outcome**

In `app/services/checks_episode_creation_permission.rb`, change the `call` method (lines 12-22):

From:
```ruby
  def call
    return Result.allowed if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = FREE_MONTHLY_LIMIT - usage.episode_count

    if remaining > 0
      Result.allowed(remaining: remaining)
    else
      Result.denied
    end
  end
```

To:
```ruby
  def call
    return Outcome.success if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = FREE_MONTHLY_LIMIT - usage.episode_count

    if remaining > 0
      Outcome.success(nil, remaining: remaining)
    else
      Outcome.failure("Episode limit reached")
    end
  end
```

**Step 3: Delete the inline Result class**

Delete lines 33-56 (the entire `class Result ... end` block).

**Step 4: Update controller call site**

In `app/controllers/episodes_controller.rb`, line 91:

From:
```ruby
return if result.allowed?
```

To:
```ruby
return if result.success?
```

**Step 5: Update tests**

In `test/services/checks_episode_creation_permission_test.rb`, replace:
- `result.allowed?` → `result.success?`
- `result.denied?` → `result.failure?`
- `result.remaining` → `result.data&.dig(:remaining)` or check `result.data[:remaining]`

For lines checking `remaining`:
- `assert_nil result.remaining` → `assert_nil result.data`
- `assert_equal 2, result.remaining` → `assert_equal 2, result.data[:remaining]`
- `assert_equal 1, result.remaining` → `assert_equal 1, result.data[:remaining]`
- `assert_equal 0, result.remaining` → For denied case, `result.data` is nil

Full test file replacement:

```ruby
require "test_helper"

class ChecksEpisodeCreationPermissionTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @premium_user = users(:premium_user)
    @unlimited_user = users(:unlimited_user)
  end

  test "returns success for premium user" do
    result = ChecksEpisodeCreationPermission.call(user: @premium_user)

    assert result.success?
    refute result.failure?
    assert_nil result.data
  end

  test "returns success for unlimited user" do
    result = ChecksEpisodeCreationPermission.call(user: @unlimited_user)

    assert result.success?
    assert_nil result.data
  end

  test "returns success with remaining count for free user with no usage" do
    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.success?
    assert_equal 2, result.data[:remaining]
  end

  test "returns success with remaining count for free user with 1 episode" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 1
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.success?
    assert_equal 1, result.data[:remaining]
  end

  test "returns failure for free user at limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.failure?
    refute result.success?
    assert_equal "Episode limit reached", result.message
  end

  test "returns failure for free user over limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 3
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.failure?
  end

  test "only counts current month usage" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: 1.month.ago.beginning_of_month.to_date,
      episode_count: 5
    )

    result = ChecksEpisodeCreationPermission.call(user: @free_user)

    assert result.success?
    assert_equal 2, result.data[:remaining]
  end
end
```

**Step 6: Run all affected tests**

Run: `bin/rails test test/services/checks_episode_creation_permission_test.rb test/controllers/episodes_controller_test.rb`

Expected: All tests pass

**Step 7: Commit**

```bash
git add app/services/checks_episode_creation_permission.rb app/controllers/episodes_controller.rb test/services/checks_episode_creation_permission_test.rb
git commit -m "refactor: Migrate ChecksEpisodeCreationPermission to shared Outcome class"
```

---

## Task 10: Run Full Test Suite and Verify

**Step 1: Run all tests**

Run: `bin/rails test`

Expected: All tests pass with no failures

**Step 2: Search for any remaining inline Result classes**

Run: `grep -r "class Result" app/services/`

Expected: No matches (all inline Result classes have been removed)

**Step 3: Commit final verification**

If all tests pass and no inline Result classes remain, the refactoring is complete.

```bash
git log --oneline -10
```

Expected output shows 9 commits from this refactoring:
1. feat: Add shared Result class for service return values
2. feat: Add shared Outcome class for permission checks
3. refactor: Migrate CreateUrlEpisode to shared Result class
4. refactor: Migrate CreatePasteEpisode to shared Result class
5. refactor: Migrate CreateFileEpisode to shared Result class
6. refactor: Migrate FetchesUrl to shared Result class
7. refactor: Migrate ExtractsArticle to shared Result with ArticleData struct
8. refactor: Migrate ProcessesWithLlm to shared Result with LlmData struct
9. refactor: Migrate ChecksEpisodeCreationPermission to shared Outcome class

---

## Summary

| Service | Before | After |
|---------|--------|-------|
| `CreateUrlEpisode` | `Result.success(episode)` → `result.episode` | `Result.success(episode)` → `result.data` |
| `CreatePasteEpisode` | `Result.success(episode)` → `result.episode` | `Result.success(episode)` → `result.data` |
| `CreateFileEpisode` | `Result.success(episode)` → `result.episode` | `Result.success(episode)` → `result.data` |
| `FetchesUrl` | `Result.success(html)` → `result.html` | `Result.success(html)` → `result.data` |
| `ExtractsArticle` | `Result.success(text, title:, author:)` → `result.text` | `Result.success(ArticleData.new(...))` → `result.data.text` |
| `ProcessesWithLlm` | `Result.success(**kwargs)` → `result.title` | `Result.success(LlmData.new(...))` → `result.data.title` |
| `ChecksEpisodeCreationPermission` | `Result.allowed/denied` → `result.allowed?` | `Outcome.success/failure` → `result.success?` |
