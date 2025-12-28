# Centralize Configuration Constants Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate all scattered business logic constants into a single `AppConfig` class with nested modules.

**Architecture:** Create `app/models/app_config.rb` with nested modules (`Tiers`, `Content`, `Llm`, `Network`) containing all constants. Helper methods like `character_limit_for(tier)` replace scattered case statements. Voice model becomes a pure data catalog.

**Tech Stack:** Ruby, Rails, Minitest

---

## Task 1: Create AppConfig with Tests

**Files:**
- Create: `test/models/app_config_test.rb`
- Create: `app/models/app_config.rb`

**Step 1: Write the failing test for AppConfig::Tiers**

```ruby
# test/models/app_config_test.rb
# frozen_string_literal: true

require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  test "FREE_CHARACTER_LIMIT is 15000" do
    assert_equal 15_000, AppConfig::Tiers::FREE_CHARACTER_LIMIT
  end

  test "PREMIUM_CHARACTER_LIMIT is 50000" do
    assert_equal 50_000, AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT
  end

  test "FREE_MONTHLY_EPISODES is 2" do
    assert_equal 2, AppConfig::Tiers::FREE_MONTHLY_EPISODES
  end

  test "character_limit_for free tier returns FREE_CHARACTER_LIMIT" do
    assert_equal 15_000, AppConfig::Tiers.character_limit_for("free")
  end

  test "character_limit_for premium tier returns PREMIUM_CHARACTER_LIMIT" do
    assert_equal 50_000, AppConfig::Tiers.character_limit_for("premium")
  end

  test "character_limit_for unlimited tier returns nil" do
    assert_nil AppConfig::Tiers.character_limit_for("unlimited")
  end

  test "FREE_VOICES contains four standard voices" do
    assert_equal %w[wren felix sloane archer], AppConfig::Tiers::FREE_VOICES
  end

  test "UNLIMITED_VOICES contains all eight voices" do
    assert_equal 8, AppConfig::Tiers::UNLIMITED_VOICES.length
    assert_includes AppConfig::Tiers::UNLIMITED_VOICES, "wren"
    assert_includes AppConfig::Tiers::UNLIMITED_VOICES, "elara"
  end

  test "voices_for free tier returns FREE_VOICES" do
    assert_equal AppConfig::Tiers::FREE_VOICES, AppConfig::Tiers.voices_for("free")
  end

  test "voices_for premium tier returns FREE_VOICES" do
    assert_equal AppConfig::Tiers::FREE_VOICES, AppConfig::Tiers.voices_for("premium")
  end

  test "voices_for unlimited tier returns UNLIMITED_VOICES" do
    assert_equal AppConfig::Tiers::UNLIMITED_VOICES, AppConfig::Tiers.voices_for("unlimited")
  end

  test "Content::MIN_LENGTH is 100" do
    assert_equal 100, AppConfig::Content::MIN_LENGTH
  end

  test "Content::MAX_FETCH_BYTES is 10MB" do
    assert_equal 10 * 1024 * 1024, AppConfig::Content::MAX_FETCH_BYTES
  end

  test "Llm::MAX_INPUT_CHARS is 100000" do
    assert_equal 100_000, AppConfig::Llm::MAX_INPUT_CHARS
  end

  test "Llm::MAX_TITLE_LENGTH is 255" do
    assert_equal 255, AppConfig::Llm::MAX_TITLE_LENGTH
  end

  test "Llm::MAX_AUTHOR_LENGTH is 255" do
    assert_equal 255, AppConfig::Llm::MAX_AUTHOR_LENGTH
  end

  test "Llm::MAX_DESCRIPTION_LENGTH is 1000" do
    assert_equal 1000, AppConfig::Llm::MAX_DESCRIPTION_LENGTH
  end

  test "Network::TIMEOUT_SECONDS is 10" do
    assert_equal 10, AppConfig::Network::TIMEOUT_SECONDS
  end

  test "Network::DNS_TIMEOUT_SECONDS is 5" do
    assert_equal 5, AppConfig::Network::DNS_TIMEOUT_SECONDS
  end
end
```

**Step 2: Run test to verify it fails**

Run: `rake test TEST=test/models/app_config_test.rb`
Expected: FAIL with "uninitialized constant AppConfig"

**Step 3: Write the AppConfig implementation**

```ruby
# app/models/app_config.rb
# frozen_string_literal: true

class AppConfig
  module Tiers
    FREE_CHARACTER_LIMIT = 15_000
    PREMIUM_CHARACTER_LIMIT = 50_000
    FREE_MONTHLY_EPISODES = 2

    FREE_VOICES = %w[wren felix sloane archer].freeze
    PREMIUM_VOICES = FREE_VOICES
    UNLIMITED_VOICES = (FREE_VOICES + %w[elara callum lark nash]).freeze

    def self.character_limit_for(tier)
      case tier.to_s
      when "free" then FREE_CHARACTER_LIMIT
      when "premium" then PREMIUM_CHARACTER_LIMIT
      when "unlimited" then nil
      end
    end

    def self.voices_for(tier)
      case tier.to_s
      when "free", "premium" then FREE_VOICES
      when "unlimited" then UNLIMITED_VOICES
      end
    end
  end

  module Content
    MIN_LENGTH = 100
    MAX_FETCH_BYTES = 10 * 1024 * 1024  # 10MB
  end

  module Llm
    MAX_INPUT_CHARS = 100_000
    MAX_TITLE_LENGTH = 255
    MAX_AUTHOR_LENGTH = 255
    MAX_DESCRIPTION_LENGTH = 1000
  end

  module Network
    TIMEOUT_SECONDS = 10
    DNS_TIMEOUT_SECONDS = 5
  end
end
```

**Step 4: Run test to verify it passes**

Run: `rake test TEST=test/models/app_config_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add test/models/app_config_test.rb app/models/app_config.rb
git commit -m "feat: add AppConfig class with centralized constants"
```

---

## Task 2: Refactor Voice Model

**Files:**
- Modify: `app/models/voice.rb:3-6` (remove STANDARD, CHIRP, update ALL)
- Modify: `app/models/voice.rb:22-24` (remove for_tier method)
- Modify: `test/models/voice_test.rb` (update tests)

**Step 1: Update voice_test.rb to test new behavior**

Remove tests for `STANDARD`, `CHIRP`, and `for_tier`. Update `ALL` test.

```ruby
# test/models/voice_test.rb
# frozen_string_literal: true

require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  test "ALL contains all eight voices from CATALOG" do
    assert_equal 8, Voice::ALL.length
    assert_includes Voice::ALL, "wren"
    assert_includes Voice::ALL, "elara"
  end

  test "find returns voice data for valid key" do
    voice = Voice.find("wren")

    assert_equal "Wren", voice[:name]
    assert_equal "British", voice[:accent]
    assert_equal "Female", voice[:gender]
    assert_equal "en-GB-Standard-C", voice[:google_voice]
  end

  test "find returns nil for invalid key" do
    assert_nil Voice.find("invalid")
  end

  test "sample_url returns GCS URL for voice" do
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    assert_equal "https://storage.googleapis.com/test-bucket/voices/wren.mp3", Voice.sample_url("wren")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `rake test TEST=test/models/voice_test.rb`
Expected: FAIL (tests reference removed constants)

**Step 3: Update Voice model**

```ruby
# app/models/voice.rb
# frozen_string_literal: true

class Voice
  CATALOG = {
    "wren"    => { name: "Wren",    accent: "British",  gender: "Female", google_voice: "en-GB-Standard-C" },
    "felix"   => { name: "Felix",   accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-D" },
    "sloane"  => { name: "Sloane",  accent: "American", gender: "Female", google_voice: "en-US-Standard-C" },
    "archer"  => { name: "Archer",  accent: "American", gender: "Male",   google_voice: "en-US-Standard-J" },
    "elara"   => { name: "Elara",   accent: "British",  gender: "Female", google_voice: "en-GB-Chirp3-HD-Gacrux" },
    "callum"  => { name: "Callum",  accent: "British",  gender: "Male",   google_voice: "en-GB-Chirp3-HD-Enceladus" },
    "lark"    => { name: "Lark",    accent: "American", gender: "Female", google_voice: "en-US-Chirp3-HD-Callirrhoe" },
    "nash"    => { name: "Nash",    accent: "American", gender: "Male",   google_voice: "en-US-Chirp3-HD-Charon" }
  }.freeze

  ALL = CATALOG.keys.freeze

  DEFAULT_STANDARD = "en-GB-Standard-D"
  DEFAULT_CHIRP = "en-GB-Chirp3-HD-Enceladus"

  def self.sample_url(key)
    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    "https://storage.googleapis.com/#{bucket}/voices/#{key}.mp3"
  end

  def self.find(key)
    CATALOG[key]
  end
end
```

**Step 4: Run test to verify it passes**

Run: `rake test TEST=test/models/voice_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/models/voice.rb test/models/voice_test.rb
git commit -m "refactor: simplify Voice to pure data catalog"
```

---

## Task 3: Update User Model

**Files:**
- Modify: `app/models/user.rb:28-30` (update available_voices method)
- Modify: `test/models/user_test.rb:153-165` (update available_voices tests)

**Step 1: Update user_test.rb tests for available_voices**

Replace references to `Voice::STANDARD` and `Voice::ALL` with `AppConfig::Tiers` equivalents:

```ruby
# In test/models/user_test.rb, replace lines 153-165 with:

  test "available_voices returns FREE_VOICES for free tier" do
    user = users(:one)
    user.tier = :free

    assert_equal AppConfig::Tiers::FREE_VOICES, user.available_voices
  end

  test "available_voices returns UNLIMITED_VOICES for unlimited tier" do
    user = users(:one)
    user.tier = :unlimited

    assert_equal AppConfig::Tiers::UNLIMITED_VOICES, user.available_voices
  end
```

**Step 2: Run test to verify it fails**

Run: `rake test TEST=test/models/user_test.rb`
Expected: FAIL (available_voices still returns Voice::STANDARD)

**Step 3: Update User#available_voices**

In `app/models/user.rb`, change line 28-30 from:

```ruby
  def available_voices
    Voice.for_tier(tier)
  end
```

to:

```ruby
  def available_voices
    AppConfig::Tiers.voices_for(tier)
  end
```

**Step 4: Run test to verify it passes**

Run: `rake test TEST=test/models/user_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "refactor: use AppConfig for available_voices"
```

---

## Task 4: Update ValidatesEpisodeSubmission

**Files:**
- Modify: `app/services/validates_episode_submission.rb:4-5,25-31`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/validates_episode_submission_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update ValidatesEpisodeSubmission**

Replace the entire file with:

```ruby
# app/services/validates_episode_submission.rb
# frozen_string_literal: true

class ValidatesEpisodeSubmission
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    ValidationResult.success(
      max_characters: max_characters_for_user
    )
  end

  private

  attr_reader :user

  def max_characters_for_user
    AppConfig::Tiers.character_limit_for(user.tier)
  end

  class ValidationResult
    attr_reader :max_characters

    def self.success(max_characters:)
      new(max_characters: max_characters)
    end

    def initialize(max_characters:)
      @max_characters = max_characters
    end

    def unlimited?
      max_characters.nil?
    end
  end
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/validates_episode_submission_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/validates_episode_submission.rb
git commit -m "refactor: use AppConfig in ValidatesEpisodeSubmission"
```

---

## Task 5: Update CalculatesMaxCharactersForUser

**Files:**
- Modify: `app/services/calculates_max_characters_for_user.rb`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/calculates_max_characters_for_user_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update CalculatesMaxCharactersForUser**

Replace entire file with:

```ruby
# app/services/calculates_max_characters_for_user.rb
# frozen_string_literal: true

class CalculatesMaxCharactersForUser
  def self.call(user:)
    AppConfig::Tiers.character_limit_for(user.tier)
  end
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/calculates_max_characters_for_user_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/calculates_max_characters_for_user.rb
git commit -m "refactor: simplify CalculatesMaxCharactersForUser to use AppConfig"
```

---

## Task 6: Update ChecksEpisodeCreationPermission

**Files:**
- Modify: `app/services/checks_episode_creation_permission.rb:4,18`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/checks_episode_creation_permission_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update ChecksEpisodeCreationPermission**

Replace entire file with:

```ruby
# app/services/checks_episode_creation_permission.rb
# frozen_string_literal: true

class ChecksEpisodeCreationPermission
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Outcome.success if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = AppConfig::Tiers::FREE_MONTHLY_EPISODES - usage.episode_count

    if remaining > 0
      Outcome.success(nil, remaining: remaining)
    else
      Outcome.failure("Episode limit reached")
    end
  end

  private

  attr_reader :user

  def skip_tracking?
    !user.free?
  end
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/checks_episode_creation_permission_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/checks_episode_creation_permission.rb
git commit -m "refactor: use AppConfig in ChecksEpisodeCreationPermission"
```

---

## Task 7: Update ExtractsArticle

**Files:**
- Modify: `app/services/extracts_article.rb:6-7,27-28,36-37,65`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/extracts_article_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update ExtractsArticle**

Replace the constant definitions and their usages. The full file becomes:

```ruby
# app/services/extracts_article.rb
# frozen_string_literal: true

class ExtractsArticle
  REMOVE_TAGS = %w[script style nav footer header aside form noscript iframe].freeze
  CONTENT_SELECTORS = %w[article main body].freeze

  ArticleData = Struct.new(:text, :title, :author, keyword_init: true) do
    def character_count
      text&.length || 0
    end
  end

  def self.call(html:)
    new(html: html).call
  end

  def initialize(html:)
    @html = html
  end

  def call
    html_size = html.bytesize
    Rails.logger.info "event=article_extraction_request html_bytes=#{html_size}"

    if html_size > AppConfig::Content::MAX_FETCH_BYTES
      Rails.logger.warn "event=article_extraction_too_large html_bytes=#{html_size} max_bytes=#{AppConfig::Content::MAX_FETCH_BYTES}"
      return Result.failure("Article content too large")
    end

    doc = Nokogiri::HTML(html)
    remove_unwanted_elements(doc)
    text = extract_content(doc)

    if text.length < AppConfig::Content::MIN_LENGTH
      Rails.logger.warn "event=article_extraction_insufficient_content extracted_chars=#{text.length} min_required=#{AppConfig::Content::MIN_LENGTH}"
      return Result.failure("Could not extract article content")
    end

    Rails.logger.info "event=article_extraction_success extracted_chars=#{text.length}"
    Result.success(ArticleData.new(text: text, title: extract_title(doc), author: extract_author(doc)))
  end

  private

  attr_reader :html

  def remove_unwanted_elements(doc)
    REMOVE_TAGS.each do |tag|
      doc.css(tag).remove
    end
  end

  def extract_content(doc)
    content_node = find_content_node(doc)
    return "" unless content_node

    content_node.text.gsub(/\s+/, " ").strip
  end

  def find_content_node(doc)
    CONTENT_SELECTORS.each do |selector|
      node = doc.at_css(selector)
      return node if node && node.text.strip.length >= AppConfig::Content::MIN_LENGTH
    end
    nil
  end

  def extract_title(doc)
    doc.at_css("title")&.text&.strip.presence
  end

  def extract_author(doc)
    doc.at_css('meta[name="author"]')&.[]("content")&.strip.presence
  end
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/extracts_article_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/extracts_article.rb
git commit -m "refactor: use AppConfig::Content in ExtractsArticle"
```

---

## Task 8: Update CreatePasteEpisode

**Files:**
- Modify: `app/services/create_paste_episode.rb:4,18`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/create_paste_episode_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update CreatePasteEpisode**

Replace entire file with:

```ruby
# app/services/create_paste_episode.rb
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
    return Result.failure("Text cannot be empty") if text.blank?
    return Result.failure("Text must be at least #{AppConfig::Content::MIN_LENGTH} characters") if text.length < AppConfig::Content::MIN_LENGTH
    return Result.failure(max_characters_error) if exceeds_max_characters?

    episode = create_episode
    ProcessPasteEpisodeJob.perform_later(episode.id)

    Rails.logger.info "event=paste_episode_created episode_id=#{episode.id} text_length=#{text.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :text

  def exceeds_max_characters?
    max_chars = CalculatesMaxCharactersForUser.call(user: user)
    max_chars && text.length > max_chars
  end

  def max_characters_error
    max_chars = CalculatesMaxCharactersForUser.call(user: user)
    "Text is too long for your account tier (#{text.length} characters, max #{max_chars})"
  end

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
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/create_paste_episode_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/create_paste_episode.rb
git commit -m "refactor: use AppConfig::Content in CreatePasteEpisode"
```

---

## Task 9: Update FetchesUrl

**Files:**
- Modify: `app/services/fetches_url.rb:4-6,44-45,58-59,86,105-106,120`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/fetches_url_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update FetchesUrl**

Replace entire file with:

```ruby
# app/services/fetches_url.rb
# frozen_string_literal: true

class FetchesUrl
  # SSRF protection: block private/internal IP ranges
  BLOCKED_IP_RANGES = [
    IPAddr.new("127.0.0.0/8"),       # Loopback
    IPAddr.new("10.0.0.0/8"),        # Private class A
    IPAddr.new("172.16.0.0/12"),     # Private class B
    IPAddr.new("192.168.0.0/16"),    # Private class C
    IPAddr.new("169.254.0.0/16"),    # Link-local / cloud metadata
    IPAddr.new("0.0.0.0/8"),         # Current network
    IPAddr.new("::1/128"),           # IPv6 loopback
    IPAddr.new("fc00::/7"),          # IPv6 private
    IPAddr.new("fe80::/10")          # IPv6 link-local
  ].freeze

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    unless valid_url?
      Rails.logger.warn "event=url_validation_failed url=#{url}"
      return Result.failure("Invalid URL")
    end

    unless safe_host?
      Rails.logger.warn "event=url_blocked_internal url=#{url}"
      return Result.failure("URL not allowed")
    end

    # Check Content-Length via HEAD request first (if available)
    head_response = connection.head(url)
    content_length = head_response.headers["content-length"]&.to_i

    if content_length && content_length > AppConfig::Content::MAX_FETCH_BYTES
      Rails.logger.warn "event=url_fetch_too_large url=#{url} content_length=#{content_length} max=#{AppConfig::Content::MAX_FETCH_BYTES}"
      return Result.failure("Content too large")
    end

    Rails.logger.info "event=url_fetch_request url=#{url}"
    response = connection.get(url)

    unless response.success?
      Rails.logger.warn "event=url_fetch_http_error url=#{url} status=#{response.status}"
      return Result.failure("Could not fetch URL")
    end

    # Double-check actual body size
    if response.body.bytesize > AppConfig::Content::MAX_FETCH_BYTES
      Rails.logger.warn "event=url_fetch_body_too_large url=#{url} bytes=#{response.body.bytesize}"
      return Result.failure("Content too large")
    end

    Rails.logger.info "event=url_fetch_success url=#{url} status=#{response.status} bytes=#{response.body.bytesize}"
    Result.success(response.body)
  rescue Faraday::TimeoutError
    Rails.logger.warn "event=url_fetch_timeout url=#{url}"
    Result.failure("Could not fetch URL")
  rescue Faraday::ConnectionFailed => e
    Rails.logger.warn "event=url_fetch_connection_failed url=#{url} error=#{e.message}"
    Result.failure("Could not fetch URL")
  end

  private

  attr_reader :url

  def valid_url?
    ValidatesUrl.valid?(url)
  end

  def safe_host?
    uri = URI.parse(url)
    return false if uri.host.nil?

    # Resolve DNS to check actual IP (with timeout)
    addresses = Timeout.timeout(AppConfig::Network::DNS_TIMEOUT_SECONDS) do
      Resolv.getaddresses(uri.host)
    end
    return false if addresses.empty?

    addresses.none? { |addr| blocked_ip?(addr) }
  rescue Resolv::ResolvError, Timeout::Error
    false
  end

  def blocked_ip?(ip_string)
    ip = IPAddr.new(ip_string)
    BLOCKED_IP_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true # Block if we can't parse the IP
  end

  def connection
    Faraday.new do |f|
      f.options.timeout = AppConfig::Network::TIMEOUT_SECONDS
      f.options.open_timeout = AppConfig::Network::TIMEOUT_SECONDS
      f.response :follow_redirects, callback: method(:validate_redirect_target)
      f.adapter Faraday.default_adapter
    end
  end

  # Callback to validate each redirect target against SSRF blocklist
  # This prevents DNS rebinding attacks where initial DNS is safe but redirect resolves to internal IP
  def validate_redirect_target(_old_env, new_env)
    new_url = new_env[:url].to_s
    new_uri = URI.parse(new_url)

    return if new_uri.host.nil?

    addresses = Timeout.timeout(AppConfig::Network::DNS_TIMEOUT_SECONDS) do
      Resolv.getaddresses(new_uri.host)
    end

    if addresses.empty? || addresses.any? { |addr| blocked_ip?(addr) }
      Rails.logger.warn "event=redirect_blocked_internal url=#{new_url}"
      raise Faraday::ConnectionFailed, "Redirect to blocked address"
    end
  rescue Resolv::ResolvError, Timeout::Error
    Rails.logger.warn "event=redirect_dns_failed url=#{new_url}"
    raise Faraday::ConnectionFailed, "Redirect DNS resolution failed"
  end
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/fetches_url_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/fetches_url.rb
git commit -m "refactor: use AppConfig::Content and Network in FetchesUrl"
```

---

## Task 10: Update ProcessesWithLlm

**Files:**
- Modify: `app/services/processes_with_llm.rb:4-7,23-24,81-83`

**Step 1: Run existing tests to verify current behavior**

Run: `rake test TEST=test/services/processes_with_llm_test.rb`
Expected: All tests PASS (baseline)

**Step 2: Update ProcessesWithLlm**

Replace entire file with:

```ruby
# app/services/processes_with_llm.rb
# frozen_string_literal: true

class ProcessesWithLlm
  LlmData = Struct.new(:title, :author, :description, :content, keyword_init: true)

  def self.call(text:, episode:)
    new(text: text, episode: episode).call
  end

  def initialize(text:, episode:)
    @text = text
    @episode = episode
  end

  def call
    Rails.logger.info "event=llm_request_started episode_id=#{episode.id} input_chars=#{text.length}"

    if text.length > AppConfig::Llm::MAX_INPUT_CHARS
      Rails.logger.warn "event=llm_input_too_large episode_id=#{episode.id} input_chars=#{text.length} max_chars=#{AppConfig::Llm::MAX_INPUT_CHARS}"
      return Result.failure("Article content too large for processing")
    end

    prompt = build_prompt
    response = llm_client.ask(prompt)

    Rails.logger.info "event=llm_response_received episode_id=#{episode.id} input_tokens=#{response.input_tokens} output_tokens=#{response.output_tokens}"

    parsed = parse_response(response.content)
    validated = validate_and_sanitize(parsed)
    RecordLlmUsage.call(episode: episode, response: response)

    Rails.logger.info "event=llm_request_completed episode_id=#{episode.id} extracted_title=#{validated[:title]}"

    Result.success(LlmData.new(**validated))
  rescue RubyLLM::Error => e
    Rails.logger.error "event=llm_api_error episode_id=#{episode.id} error=#{e.class} message=#{e.message}"

    Result.failure("Failed to process content")
  rescue JSON::ParserError => e
    Rails.logger.error "event=llm_json_parse_error episode_id=#{episode.id} error=#{e.message}"

    Result.failure("Failed to process content")
  rescue ValidationError => e
    Rails.logger.error "event=llm_validation_error episode_id=#{episode.id} error=#{e.message}"

    Result.failure("Failed to process content")
  end

  private

  attr_reader :text, :episode

  def llm_client
    @llm_client ||= AsksLlm.new
  end

  def build_prompt
    if episode.paste?
      BuildsPasteProcessingPrompt.call(text: text)
    else
      BuildsUrlProcessingPrompt.call(text: text)
    end
  end

  def parse_response(content)
    # Strip markdown code blocks if present
    json_content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
    JSON.parse(json_content)
  end

  def validate_and_sanitize(parsed)
    content = extract_string(parsed, "content")
    raise ValidationError, "Missing content in LLM response" if content.blank?

    {
      title: truncate(extract_string(parsed, "title", "Untitled"), AppConfig::Llm::MAX_TITLE_LENGTH),
      author: truncate(extract_string(parsed, "author", "Unknown"), AppConfig::Llm::MAX_AUTHOR_LENGTH),
      description: truncate(extract_string(parsed, "description", ""), AppConfig::Llm::MAX_DESCRIPTION_LENGTH),
      content: content
    }
  end

  def extract_string(hash, key, default = nil)
    value = hash[key]
    return default unless value.is_a?(String)

    value.strip.presence || default
  end

  def truncate(string, max_length)
    return "" if string.nil?

    string.length > max_length ? "#{string[0, max_length - 3]}..." : string
  end

  class ValidationError < StandardError; end
end
```

**Step 3: Run test to verify it still passes**

Run: `rake test TEST=test/services/processes_with_llm_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add app/services/processes_with_llm.rb
git commit -m "refactor: use AppConfig::Llm in ProcessesWithLlm"
```

---

## Task 11: Run Full Test Suite and Verify

**Step 1: Run the full test suite**

Run: `rake test`
Expected: All tests PASS

**Step 2: Grep verification to ensure no orphaned constants**

Run these commands to verify all old constants are removed:

```bash
grep -rn "MAX_CHARACTERS_FREE\|MAX_CHARACTERS_PREMIUM" app/
grep -rn "MIN_CONTENT_LENGTH\|MINIMUM_LENGTH" app/
grep -rn "MAX_HTML_BYTES\|MAX_CONTENT_LENGTH" app/
grep -rn "FREE_MONTHLY_LIMIT" app/
grep -rn "MAX_INPUT_CHARS\|MAX_TITLE_LENGTH\|MAX_AUTHOR_LENGTH\|MAX_DESCRIPTION_LENGTH" app/
grep -rn "TIMEOUT_SECONDS\|DNS_TIMEOUT_SECONDS" app/
grep -rn "Voice::STANDARD\|Voice::CHIRP\|Voice.for_tier" app/
```

Expected: No matches in service files (only in `app_config.rb` if any)

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: verify centralized config migration complete"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `app/models/app_config.rb` | NEW - centralized constants |
| `test/models/app_config_test.rb` | NEW - tests for AppConfig |
| `app/models/voice.rb` | Removed STANDARD, CHIRP, for_tier; ALL now from CATALOG.keys |
| `test/models/voice_test.rb` | Removed tests for STANDARD, CHIRP, for_tier |
| `app/models/user.rb` | available_voices uses AppConfig::Tiers.voices_for |
| `test/models/user_test.rb` | Updated available_voices tests |
| `app/services/validates_episode_submission.rb` | Removed constants, uses AppConfig::Tiers |
| `app/services/calculates_max_characters_for_user.rb` | Simplified to one-liner using AppConfig |
| `app/services/checks_episode_creation_permission.rb` | Uses AppConfig::Tiers::FREE_MONTHLY_EPISODES |
| `app/services/extracts_article.rb` | Uses AppConfig::Content |
| `app/services/create_paste_episode.rb` | Uses AppConfig::Content::MIN_LENGTH |
| `app/services/fetches_url.rb` | Uses AppConfig::Content and Network |
| `app/services/processes_with_llm.rb` | Uses AppConfig::Llm |
