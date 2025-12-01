# HTML Metadata Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract title and author from HTML metadata tags, using them as primary source with LLM as fallback.

**Architecture:** Extend `ArticleExtractor` to return metadata alongside text. `ProcessUrlEpisode` merges HTML metadata (wins) with LLM results (fallback).

**Tech Stack:** Ruby, Nokogiri, Minitest

---

### Task 1: Add metadata extraction tests to ArticleExtractor

**Files:**
- Modify: `test/services/article_extractor_test.rb`

**Step 1: Write the failing test for title extraction**

Add to `test/services/article_extractor_test.rb`:

```ruby
test "extracts title from title tag" do
  html = <<~HTML
    <html>
      <head><title>My Article Title</title></head>
      <body>
        <article>
          <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
        </article>
      </body>
    </html>
  HTML

  result = ArticleExtractor.call(html: html)

  assert result.success?
  assert_equal "My Article Title", result.title
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/article_extractor_test.rb:145 -v`

Expected: FAIL with "undefined method `title'"

**Step 3: Write the failing test for author extraction**

Add to `test/services/article_extractor_test.rb`:

```ruby
test "extracts author from meta tag" do
  html = <<~HTML
    <html>
      <head>
        <title>Article</title>
        <meta name="author" content="Jane Smith">
      </head>
      <body>
        <article>
          <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
        </article>
      </body>
    </html>
  HTML

  result = ArticleExtractor.call(html: html)

  assert result.success?
  assert_equal "Jane Smith", result.author
end
```

**Step 4: Run test to verify it fails**

Run: `bin/rails test test/services/article_extractor_test.rb:163 -v`

Expected: FAIL with "undefined method `author'"

**Step 5: Write test for missing metadata**

Add to `test/services/article_extractor_test.rb`:

```ruby
test "returns nil for missing metadata" do
  html = <<~HTML
    <html>
      <body>
        <article>
          <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
        </article>
      </body>
    </html>
  HTML

  result = ArticleExtractor.call(html: html)

  assert result.success?
  assert_nil result.title
  assert_nil result.author
end
```

**Step 6: Run test to verify it fails**

Run: `bin/rails test test/services/article_extractor_test.rb:181 -v`

Expected: FAIL with "undefined method `title'"

**Step 7: Commit test file**

```bash
git add test/services/article_extractor_test.rb
git commit -m "test: Add failing tests for HTML metadata extraction"
```

---

### Task 2: Implement metadata extraction in ArticleExtractor

**Files:**
- Modify: `app/services/article_extractor.rb:62-89` (Result class)
- Modify: `app/services/article_extractor.rb:24-34` (call method)

**Step 1: Update Result class to include metadata**

Replace the `Result` class (lines 62-89) in `app/services/article_extractor.rb`:

```ruby
class Result
  attr_reader :text, :error, :title, :author

  def self.success(text, title: nil, author: nil)
    new(text: text, error: nil, title: title, author: author)
  end

  def self.failure(error)
    new(text: nil, error: error, title: nil, author: nil)
  end

  def initialize(text:, error:, title:, author:)
    @text = text
    @error = error
    @title = title
    @author = author
  end

  def success?
    error.nil?
  end

  def failure?
    !success?
  end

  def character_count
    text&.length || 0
  end
end
```

**Step 2: Add extraction methods**

Add before the `Result` class in `app/services/article_extractor.rb`:

```ruby
def extract_title(doc)
  doc.at_css("title")&.text&.strip.presence
end

def extract_author(doc)
  doc.at_css('meta[name="author"]')&.[]("content")&.strip.presence
end
```

**Step 3: Update call method to return metadata**

Update the success path in the `call` method (around line 34):

```ruby
Rails.logger.info "event=article_extraction_success extracted_chars=#{text.length}"
Result.success(text, title: extract_title(doc), author: extract_author(doc))
```

**Step 4: Run all ArticleExtractor tests**

Run: `bin/rails test test/services/article_extractor_test.rb -v`

Expected: All tests PASS

**Step 5: Commit implementation**

```bash
git add app/services/article_extractor.rb
git commit -m "feat: Extract title and author metadata from HTML"
```

---

### Task 3: Add test for ProcessUrlEpisode HTML metadata preference

**Files:**
- Modify: `test/services/process_url_episode_test.rb`

**Step 1: Write the failing test**

Add to `test/services/process_url_episode_test.rb`:

```ruby
test "prefers HTML metadata over LLM results" do
  html = <<~HTML
    <html>
      <head>
        <title>HTML Title</title>
        <meta name="author" content="HTML Author">
      </head>
      <body>
        <article>
          <p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p>
        </article>
      </body>
    </html>
  HTML

  stubs { |m| UrlFetcher.call(url: m.any) }.with { UrlFetcher::Result.success(html) }

  mock_llm_result = LlmProcessor::Result.success(
    title: "LLM Title",
    author: "LLM Author",
    description: "LLM description.",
    content: "Article content here."
  )

  stubs { |m| LlmProcessor.call(text: m.any, episode: m.any, user: m.any) }.with { mock_llm_result }
  stub_gcs_and_tasks

  ProcessUrlEpisode.call(episode: @episode)

  @episode.reload
  assert_equal "HTML Title", @episode.title
  assert_equal "HTML Author", @episode.author
  assert_equal "LLM description.", @episode.description
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/process_url_episode_test.rb:95 -v`

Expected: FAIL with "Expected: \"HTML Title\", Actual: \"LLM Title\""

**Step 3: Commit test**

```bash
git add test/services/process_url_episode_test.rb
git commit -m "test: Add failing test for HTML metadata preference"
```

---

### Task 4: Implement metadata preference in ProcessUrlEpisode

**Files:**
- Modify: `app/services/process_url_episode.rb:85-97` (update_and_enqueue method)

**Step 1: Update merge logic**

Replace the `update_and_enqueue` method in `app/services/process_url_episode.rb`:

```ruby
def update_and_enqueue
  Episode.transaction do
    episode.update!(
      title: @extract_result.title || @llm_result.title,
      author: @extract_result.author || @llm_result.author,
      description: @llm_result.description
    )

    log_info "episode_metadata_updated"

    UploadAndEnqueueEpisode.call(episode: episode, content: @llm_result.content)
  end
end
```

**Step 2: Run all ProcessUrlEpisode tests**

Run: `bin/rails test test/services/process_url_episode_test.rb -v`

Expected: All tests PASS

**Step 3: Run full test suite**

Run: `bin/rails test`

Expected: All tests PASS

**Step 4: Commit implementation**

```bash
git add app/services/process_url_episode.rb
git commit -m "feat: Prefer HTML metadata over LLM results"
```

---

### Task 5: Final verification and cleanup

**Step 1: Run full test suite**

Run: `bin/rails test`

Expected: All tests PASS

**Step 2: Push changes**

```bash
git push origin main
```
