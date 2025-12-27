# Searls Style Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename all services to follow the VerbsNoun naming convention and extract business logic from models into POROs.

**Architecture:** Pure rename refactoring with find-and-replace across callers. No behavior changes. Models become thin wrappers delegating URL generation to new POROs.

**Tech Stack:** Ruby on Rails, Minitest

---

## Task 1: Rename ArticleExtractor → ExtractsArticle

**Files:**
- Rename: `app/services/article_extractor.rb` → `app/services/extracts_article.rb`
- Rename: `test/services/article_extractor_test.rb` → `test/services/extracts_article_test.rb`
- Modify: `app/services/url_fetcher.rb` (if referenced)

**Step 1: Rename class and file**

```ruby
# app/services/extracts_article.rb
class ExtractsArticle
  REMOVE_TAGS = %w[script style nav footer header aside form noscript iframe].freeze
  CONTENT_SELECTORS = %w[article main body].freeze
  MIN_CONTENT_LENGTH = 100
  MAX_HTML_BYTES = 10 * 1024 * 1024 # 10MB

  def self.call(html:)
    new(html: html).call
  end

  # ... rest of class unchanged
end
```

**Step 2: Rename test file and update class reference**

```ruby
# test/services/extracts_article_test.rb
require "test_helper"

class ExtractsArticleTest < ActiveSupport::TestCase
  test "extracts article content from simple HTML" do
    # ...
    result = ExtractsArticle.call(html: html)
    # ...
  end
  # Update all other test methods similarly
end
```

**Step 3: Update all callers**

Run: `grep -r "ArticleExtractor" app/ test/ --include="*.rb" -l`

Update each file to use `ExtractsArticle`.

**Step 4: Run tests to verify**

Run: `bin/rails test test/services/extracts_article_test.rb`
Expected: All tests pass

**Step 5: Delete old files and commit**

```bash
git add -A && git commit -m "refactor: rename ArticleExtractor to ExtractsArticle"
```

---

## Task 2: Rename UrlFetcher → FetchesUrl

**Files:**
- Rename: `app/services/url_fetcher.rb` → `app/services/fetches_url.rb`
- Rename: `test/services/url_fetcher_test.rb` → `test/services/fetches_url_test.rb`
- Modify: All callers

**Step 1: Rename class and file**

```ruby
# app/services/fetches_url.rb
class FetchesUrl
  TIMEOUT_SECONDS = 10
  # ... rest unchanged, just rename class
end
```

**Step 2: Rename test file and update class reference**

```ruby
# test/services/fetches_url_test.rb
require "test_helper"

class FetchesUrlTest < ActiveSupport::TestCase
  # Update all ExtractsUrl.call references to FetchesUrl.call
end
```

**Step 3: Update all callers**

Run: `grep -r "UrlFetcher" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/fetches_url_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename UrlFetcher to FetchesUrl"
```

---

## Task 3: Rename UrlValidator → ValidatesUrl

**Files:**
- Rename: `app/services/url_validator.rb` → `app/services/validates_url.rb`
- Rename: `test/services/url_validator_test.rb` → `test/services/validates_url_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/validates_url.rb
# frozen_string_literal: true

class ValidatesUrl
  def self.valid?(url)
    new(url).valid?
  end

  def initialize(url)
    @url = url
  end

  def valid?
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  private

  attr_reader :url
end
```

**Step 2: Rename test file and update references**

**Step 3: Update all callers**

Run: `grep -r "UrlValidator" app/ test/ --include="*.rb" -l`

The main caller is `FetchesUrl` (after Task 2).

**Step 4: Run tests**

Run: `bin/rails test test/services/validates_url_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename UrlValidator to ValidatesUrl"
```

---

## Task 4: Rename UrlNormalizer → NormalizesUrl

**Files:**
- Rename: `app/services/url_normalizer.rb` → `app/services/normalizes_url.rb`
- Rename: `test/services/url_normalizer_test.rb` → `test/services/normalizes_url_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/normalizes_url.rb
# frozen_string_literal: true

class NormalizesUrl
  SUBSTACK_TRACKING_PARAMS = %w[
    r
    utm_campaign
    utm_medium
    utm_source
    showWelcomeOnShare
    triedRedirect
  ].freeze

  def self.call(url:)
    new(url: url).call
  end
  # ... rest unchanged
end
```

**Step 2: Rename test and update references**

**Step 3: Update all callers**

Run: `grep -r "UrlNormalizer" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/normalizes_url_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename UrlNormalizer to NormalizesUrl"
```

---

## Task 5: Convert MarkdownStripper module → StripsMarkdown class

**Files:**
- Modify: `app/services/markdown_stripper.rb` → `app/services/strips_markdown.rb`
- Rename: `test/services/markdown_stripper_test.rb` → `test/services/strips_markdown_test.rb`

**Step 1: Convert module to class with call pattern**

```ruby
# app/services/strips_markdown.rb
# frozen_string_literal: true

# Strips markdown syntax from text, leaving only plain text content.
# Used by ContentPreview for episode cards and by UploadAndEnqueueEpisode
# to convert markdown to plain text before sending to TTS processing.
class StripsMarkdown
  def self.call(text)
    new(text).call
  end

  def initialize(text)
    @text = text
  end

  def call
    return text if text.nil?
    return text if text.empty?

    result = text.dup
    result = remove_yaml_frontmatter(result)
    result = remove_code_blocks(result)
    result = remove_images(result)
    result = convert_links(result)
    result = remove_html_tags(result)
    result = remove_headers(result)
    result = remove_formatting(result)
    result = remove_strikethrough(result)
    result = remove_inline_code(result)
    result = remove_unordered_lists(result)
    result = remove_ordered_lists(result)
    result = remove_blockquotes(result)
    result = remove_horizontal_rules(result)
    clean_whitespace(result)
  end

  private

  attr_reader :text

  def remove_code_blocks(text)
    text.gsub(/```[\s\S]*?```/m, "")
  end

  def remove_inline_code(text)
    text.gsub(/`([^`]+)`/, '\1')
  end

  def remove_images(text)
    text.gsub(/!\[([^\]]*)\]\([^)]+\)/, "")
  end

  def convert_links(text)
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def remove_headers(text)
    text.gsub(/^\#{1,6}\s+/, "")
  end

  def remove_formatting(text)
    result = text.gsub(/(\*\*|__)(.*?)\1/, '\2')
    result.gsub(/(\*|_)(.*?)\1/, '\2')
  end

  def remove_strikethrough(text)
    text.gsub(/~~(.*?)~~/, '\1')
  end

  def remove_unordered_lists(text)
    text.gsub(/^\s*[-*+]\s+/, "")
  end

  def remove_ordered_lists(text)
    text.gsub(/^\s*\d+\.\s+/, "")
  end

  def remove_blockquotes(text)
    text.gsub(/^\s*>\s?/, "")
  end

  def remove_horizontal_rules(text)
    text.gsub(/^(\*{3,}|-{3,}|_{3,})$/, "")
  end

  def remove_yaml_frontmatter(text)
    text.gsub(/\A---\s*\n.*?\n---\s*\n/m, "")
  end

  def remove_html_tags(text)
    text.gsub(/<[^>]+>/, "")
  end

  def clean_whitespace(text)
    text.gsub(/\n{3,}/, "\n\n").strip
  end
end
```

**Step 2: Rename test and update references**

```ruby
# test/services/strips_markdown_test.rb
require "test_helper"

class StripsMarkdownTest < ActiveSupport::TestCase
  # Change all MarkdownStripper.strip(text) to StripsMarkdown.call(text)
end
```

**Step 3: Update all callers**

Run: `grep -r "MarkdownStripper" app/ test/ --include="*.rb" -l`

Change `MarkdownStripper.strip(text)` → `StripsMarkdown.call(text)`

**Step 4: Run tests**

Run: `bin/rails test test/services/strips_markdown_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: convert MarkdownStripper module to StripsMarkdown class"
```

---

## Task 6: Rename ContentPreview → GeneratesContentPreview

**Files:**
- Rename: `app/services/content_preview.rb` → `app/services/generates_content_preview.rb`
- Rename: `test/services/content_preview_test.rb` → `test/services/generates_content_preview_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/generates_content_preview.rb
# frozen_string_literal: true

class GeneratesContentPreview
  PREVIEW_LENGTH = 60
  ELLIPSIS = "..."

  def self.call(text)
    new(text).call
  end

  def initialize(text)
    @text = text
  end

  def call
    return nil if text.nil?

    stripped = text.strip
    return stripped if stripped.empty?

    min_truncation_length = (PREVIEW_LENGTH * 2) + 10
    return stripped if stripped.length <= min_truncation_length

    start_chars = PREVIEW_LENGTH - ELLIPSIS.length
    end_chars = PREVIEW_LENGTH - ELLIPSIS.length

    start_part = stripped[0, start_chars].strip
    end_part = stripped[-end_chars, end_chars].strip

    "#{start_part}... #{end_part}"
  end

  private

  attr_reader :text
end
```

**Step 2: Rename test and update references**

Change `ContentPreview.generate(text)` → `GeneratesContentPreview.call(text)`

**Step 3: Update all callers**

Run: `grep -r "ContentPreview" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/generates_content_preview_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename ContentPreview to GeneratesContentPreview"
```

---

## Task 7: Rename LlmClient → CallsLlm

**Files:**
- Rename: `app/services/llm_client.rb` → `app/services/calls_llm.rb`
- Rename: `test/services/llm_client_test.rb` → `test/services/calls_llm_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/calls_llm.rb
# frozen_string_literal: true

class CallsLlm
  DEFAULT_MODEL = "gemini-2.5-flash"
  PROVIDER = :vertexai

  RESPONSE_SCHEMA = {
    type: "object",
    properties: {
      title: { type: "string", description: "The title of the article" },
      author: { type: "string", description: "The author of the article" },
      description: { type: "string", description: "A brief description of the article" },
      content: { type: "string", description: "The full article content, cleaned and formatted for text-to-speech" }
    },
    required: %w[title author description content]
  }.freeze

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  def ask(prompt)
    Rails.logger.info "event=llm_client_ask model=#{model} provider=#{PROVIDER}"

    RubyLLM.chat(model: model, provider: PROVIDER)
      .with_params(generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA
      })
      .ask(prompt)
  end

  def find_model(model_id)
    RubyLLM.models.find(model_id)
  end

  private

  attr_reader :model
end
```

**Step 2: Rename test and update references**

**Step 3: Update all callers**

Run: `grep -r "LlmClient" app/ test/ --include="*.rb" -l`

Main caller is `LlmProcessor` (which becomes `ProcessesWithLlm`).

**Step 4: Run tests**

Run: `bin/rails test test/services/calls_llm_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename LlmClient to CallsLlm"
```

---

## Task 8: Rename LlmProcessor → ProcessesWithLlm

**Files:**
- Rename: `app/services/llm_processor.rb` → `app/services/processes_with_llm.rb`
- Rename: `test/services/llm_processor_test.rb` → `test/services/processes_with_llm_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/processes_with_llm.rb
# frozen_string_literal: true

class ProcessesWithLlm
  MAX_INPUT_CHARS = 100_000
  MAX_TITLE_LENGTH = 255
  MAX_AUTHOR_LENGTH = 255
  MAX_DESCRIPTION_LENGTH = 1000

  def self.call(text:, episode:)
    new(text: text, episode: episode).call
  end
  # ... rest unchanged, just rename class
end
```

**Step 2: Update internal reference to CallsLlm**

Change `LlmClient.new` → `CallsLlm.new`

**Step 3: Rename test and update references**

**Step 4: Update all callers**

Run: `grep -r "LlmProcessor" app/ test/ --include="*.rb" -l`

**Step 5: Run tests**

Run: `bin/rails test test/services/processes_with_llm_test.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: rename LlmProcessor to ProcessesWithLlm"
```

---

## Task 9: Rename UrlProcessingPrompt → BuildsUrlProcessingPrompt

**Files:**
- Rename: `app/services/url_processing_prompt.rb` → `app/services/builds_url_processing_prompt.rb`
- Rename: `test/services/url_processing_prompt_test.rb` → `test/services/builds_url_processing_prompt_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/builds_url_processing_prompt.rb
class BuildsUrlProcessingPrompt
  def self.call(text:)
    new(text: text).call
  end

  def initialize(text:)
    @text = text
  end

  def call
    <<~PROMPT
      You are processing a web article for text-to-speech conversion.
      # ... rest unchanged
    PROMPT
  end

  private

  attr_reader :text
end
```

**Step 2: Update callers**

Change `UrlProcessingPrompt.build(text:)` → `BuildsUrlProcessingPrompt.call(text:)`

**Step 3: Rename test and update references**

**Step 4: Run tests**

Run: `bin/rails test test/services/builds_url_processing_prompt_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename UrlProcessingPrompt to BuildsUrlProcessingPrompt"
```

---

## Task 10: Rename PasteProcessingPrompt → BuildsPasteProcessingPrompt

**Files:**
- Rename: `app/services/paste_processing_prompt.rb` → `app/services/builds_paste_processing_prompt.rb`
- Rename: `test/services/paste_processing_prompt_test.rb` → `test/services/builds_paste_processing_prompt_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/builds_paste_processing_prompt.rb
# frozen_string_literal: true

class BuildsPasteProcessingPrompt
  def self.call(text:)
    new(text: text).call
  end

  def initialize(text:)
    @text = text
  end

  def call
    <<~PROMPT
      You are processing pasted text for text-to-speech conversion.
      # ... rest unchanged
    PROMPT
  end

  private

  attr_reader :text
end
```

**Step 2: Update callers**

Change `PasteProcessingPrompt.build(text:)` → `BuildsPasteProcessingPrompt.call(text:)`

**Step 3: Rename test and update references**

**Step 4: Run tests**

Run: `bin/rails test test/services/builds_paste_processing_prompt_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename PasteProcessingPrompt to BuildsPasteProcessingPrompt"
```

---

## Task 11: Rename CanCreateEpisode → ChecksEpisodeCreationPermission

**Files:**
- Rename: `app/services/can_create_episode.rb` → `app/services/checks_episode_creation_permission.rb`
- Rename: `test/services/can_create_episode_test.rb` → `test/services/checks_episode_creation_permission_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/checks_episode_creation_permission.rb
class ChecksEpisodeCreationPermission
  FREE_MONTHLY_LIMIT = 2

  def self.call(user:)
    new(user: user).call
  end
  # ... rest unchanged
end
```

**Step 2: Rename test and update references**

**Step 3: Update all callers**

Run: `grep -r "CanCreateEpisode" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/checks_episode_creation_permission_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename CanCreateEpisode to ChecksEpisodeCreationPermission"
```

---

## Task 12: Rename MaxCharactersForUser → CalculatesMaxCharactersForUser

**Files:**
- Rename: `app/services/max_characters_for_user.rb` → `app/services/calculates_max_characters_for_user.rb`
- Rename: `test/services/max_characters_for_user_test.rb` → `test/services/calculates_max_characters_for_user_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/calculates_max_characters_for_user.rb
# frozen_string_literal: true

class CalculatesMaxCharactersForUser
  def self.call(user:)
    case user.tier
    when "free" then EpisodeSubmissionValidator::MAX_CHARACTERS_FREE
    when "premium" then EpisodeSubmissionValidator::MAX_CHARACTERS_PREMIUM
    when "unlimited" then nil
    end
  end
end
```

**Step 2: Rename test and update references**

**Step 3: Update all callers**

Run: `grep -r "MaxCharactersForUser" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/calculates_max_characters_for_user_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename MaxCharactersForUser to CalculatesMaxCharactersForUser"
```

---

## Task 13: Rename EpisodeSubmissionValidator → ValidatesEpisodeSubmission

**Files:**
- Rename: `app/services/episode_submission_validator.rb` → `app/services/validates_episode_submission.rb`
- Rename: `test/services/episode_submission_validator_test.rb` → `test/services/validates_episode_submission_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/validates_episode_submission.rb
class ValidatesEpisodeSubmission
  MAX_CHARACTERS_FREE = 15_000
  MAX_CHARACTERS_PREMIUM = 50_000

  def self.call(user:)
    new(user: user).call
  end
  # ... rest unchanged
end
```

**Step 2: Update CalculatesMaxCharactersForUser reference**

Change `EpisodeSubmissionValidator::MAX_CHARACTERS_FREE` → `ValidatesEpisodeSubmission::MAX_CHARACTERS_FREE`

**Step 3: Rename test and update references**

**Step 4: Update all callers**

Run: `grep -r "EpisodeSubmissionValidator" app/ test/ --include="*.rb" -l`

**Step 5: Run tests**

Run: `bin/rails test test/services/validates_episode_submission_test.rb`
Expected: All tests pass

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: rename EpisodeSubmissionValidator to ValidatesEpisodeSubmission"
```

---

## Task 14: Rename EpisodeCompletionNotifier → NotifiesEpisodeCompletion

**Files:**
- Rename: `app/services/episode_completion_notifier.rb` → `app/services/notifies_episode_completion.rb`
- Rename: `test/services/episode_completion_notifier_test.rb` → `test/services/notifies_episode_completion_test.rb`

**Step 1: Rename class and file**

```ruby
# app/services/notifies_episode_completion.rb
class NotifiesEpisodeCompletion
  def self.call(episode:)
    new(episode:).call
  end
  # ... rest unchanged
end
```

**Step 2: Rename test and update references**

**Step 3: Update all callers**

Run: `grep -r "EpisodeCompletionNotifier" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/notifies_episode_completion_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename EpisodeCompletionNotifier to NotifiesEpisodeCompletion"
```

---

## Task 15: Rename Tts::Synthesizer → SynthesizesAudio

**Files:**
- Rename: `app/services/tts.rb` → `app/services/synthesizes_audio.rb`
- Rename: `test/services/tts_test.rb` → `test/services/synthesizes_audio_test.rb`
- Keep: `app/services/tts/` subdirectory unchanged (internal implementation)

**Step 1: Rename class and file**

```ruby
# app/services/synthesizes_audio.rb
# frozen_string_literal: true

require_relative "tts/config"
require_relative "tts/api_client"
require_relative "tts/text_chunker"
require_relative "tts/chunked_synthesizer"

class SynthesizesAudio
  def initialize(config: Tts::Config.new)
    @config = config
    @api_client = Tts::ApiClient.new(config: config)
    @text_chunker = Tts::TextChunker.new
    @chunked_synthesizer = Tts::ChunkedSynthesizer.new(api_client: @api_client, config: config)
  end

  def call(text, voice: nil)
    Rails.logger.info "[TTS] Generating audio..."
    voice ||= @config.voice_name

    chunks = @text_chunker.chunk(text, @config.byte_limit)

    audio_content = if chunks.length == 1
                      @api_client.call(text: chunks[0], voice: voice)
    else
                      @chunked_synthesizer.synthesize(chunks, voice)
    end

    Rails.logger.info "[TTS] Generated #{format_size(audio_content.bytesize)}"
    audio_content
  end

  private

  def format_size(bytes)
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end
end
```

**Step 2: Rename test and update references**

Change `Tts::Synthesizer.new.synthesize(text)` → `SynthesizesAudio.new.call(text)`

**Step 3: Update all callers**

Run: `grep -r "Tts::Synthesizer" app/ test/ --include="*.rb" -l`

**Step 4: Run tests**

Run: `bin/rails test test/services/synthesizes_audio_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename Tts::Synthesizer to SynthesizesAudio"
```

---

## Task 16: Extract Episode#audio_url → GeneratesEpisodeAudioUrl

**Files:**
- Create: `app/services/generates_episode_audio_url.rb`
- Create: `test/services/generates_episode_audio_url_test.rb`
- Modify: `app/models/episode.rb`

**Step 1: Write the failing test**

```ruby
# test/services/generates_episode_audio_url_test.rb
require "test_helper"

class GeneratesEpisodeAudioUrlTest < ActiveSupport::TestCase
  test "returns nil when episode is not complete" do
    episode = episodes(:pending_episode)

    result = GeneratesEpisodeAudioUrl.call(episode)

    assert_nil result
  end

  test "returns nil when gcs_episode_id is nil" do
    episode = episodes(:complete_episode)
    episode.update!(gcs_episode_id: nil)

    result = GeneratesEpisodeAudioUrl.call(episode)

    assert_nil result
  end

  test "returns audio URL for complete episode with gcs_episode_id" do
    episode = episodes(:complete_episode)
    episode.update!(gcs_episode_id: "abc123")

    result = GeneratesEpisodeAudioUrl.call(episode)

    expected = "https://storage.googleapis.com/verynormal-tts-podcast/podcasts/#{episode.podcast.podcast_id}/episodes/abc123.mp3"
    assert_equal expected, result
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/generates_episode_audio_url_test.rb`
Expected: FAIL with "uninitialized constant GeneratesEpisodeAudioUrl"

**Step 3: Write minimal implementation**

```ruby
# app/services/generates_episode_audio_url.rb
# frozen_string_literal: true

class GeneratesEpisodeAudioUrl
  def self.call(episode)
    new(episode).call
  end

  def initialize(episode)
    @episode = episode
  end

  def call
    return nil unless episode.complete? && episode.gcs_episode_id.present?

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    podcast_id = episode.podcast.podcast_id
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/episodes/#{episode.gcs_episode_id}.mp3"
  end

  private

  attr_reader :episode
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/generates_episode_audio_url_test.rb`
Expected: PASS

**Step 5: Update Episode model to delegate**

```ruby
# app/models/episode.rb
# Change:
def audio_url
  return nil unless complete? && gcs_episode_id.present?

  bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
  podcast_id = podcast.podcast_id
  "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/episodes/#{gcs_episode_id}.mp3"
end

# To:
def audio_url
  GeneratesEpisodeAudioUrl.call(self)
end
```

**Step 6: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add -A && git commit -m "refactor: extract Episode#audio_url to GeneratesEpisodeAudioUrl"
```

---

## Task 17: Extract Podcast#feed_url → GeneratesPodcastFeedUrl

**Files:**
- Create: `app/services/generates_podcast_feed_url.rb`
- Create: `test/services/generates_podcast_feed_url_test.rb`
- Modify: `app/models/podcast.rb`

**Step 1: Write the failing test**

```ruby
# test/services/generates_podcast_feed_url_test.rb
require "test_helper"

class GeneratesPodcastFeedUrlTest < ActiveSupport::TestCase
  test "returns nil when podcast_id is blank" do
    podcast = Podcast.new(podcast_id: nil)

    result = GeneratesPodcastFeedUrl.call(podcast)

    assert_nil result
  end

  test "returns feed URL for podcast with podcast_id" do
    podcast = podcasts(:default)

    result = GeneratesPodcastFeedUrl.call(podcast)

    expected = "https://storage.googleapis.com/verynormal-tts-podcast/podcasts/#{podcast.podcast_id}/feed.xml"
    assert_equal expected, result
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/generates_podcast_feed_url_test.rb`
Expected: FAIL with "uninitialized constant GeneratesPodcastFeedUrl"

**Step 3: Write minimal implementation**

```ruby
# app/services/generates_podcast_feed_url.rb
# frozen_string_literal: true

class GeneratesPodcastFeedUrl
  def self.call(podcast)
    new(podcast).call
  end

  def initialize(podcast)
    @podcast = podcast
  end

  def call
    return nil unless podcast.podcast_id.present?

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast.podcast_id}/feed.xml"
  end

  private

  attr_reader :podcast
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/generates_podcast_feed_url_test.rb`
Expected: PASS

**Step 5: Update Podcast model to delegate**

```ruby
# app/models/podcast.rb
# Change:
def feed_url
  return nil unless podcast_id.present?

  bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
  "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/feed.xml"
end

# To:
def feed_url
  GeneratesPodcastFeedUrl.call(self)
end
```

**Step 6: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add -A && git commit -m "refactor: extract Podcast#feed_url to GeneratesPodcastFeedUrl"
```

---

## Task 18: Final verification and cleanup

**Step 1: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

**Step 2: Verify no old class names remain**

Run: `grep -rE "(ArticleExtractor|UrlFetcher|UrlValidator|UrlNormalizer|MarkdownStripper|ContentPreview|LlmClient|LlmProcessor|UrlProcessingPrompt|PasteProcessingPrompt|CanCreateEpisode|MaxCharactersForUser|EpisodeSubmissionValidator|EpisodeCompletionNotifier|Tts::Synthesizer)" app/ test/ --include="*.rb"`

Expected: No matches (or only comments/documentation)

**Step 3: Verify all new files exist**

```bash
ls -la app/services/extracts_article.rb \
       app/services/fetches_url.rb \
       app/services/validates_url.rb \
       app/services/normalizes_url.rb \
       app/services/strips_markdown.rb \
       app/services/generates_content_preview.rb \
       app/services/calls_llm.rb \
       app/services/processes_with_llm.rb \
       app/services/builds_url_processing_prompt.rb \
       app/services/builds_paste_processing_prompt.rb \
       app/services/checks_episode_creation_permission.rb \
       app/services/calculates_max_characters_for_user.rb \
       app/services/validates_episode_submission.rb \
       app/services/notifies_episode_completion.rb \
       app/services/synthesizes_audio.rb \
       app/services/generates_episode_audio_url.rb \
       app/services/generates_podcast_feed_url.rb
```

**Step 4: Final commit if any cleanup needed**

```bash
git add -A && git commit -m "chore: cleanup after Searls style refactor"
```
