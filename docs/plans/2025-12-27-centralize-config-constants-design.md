# Centralize Configuration Constants

## Problem

Business logic constants are scattered across 10+ files with duplicates and no single source of truth. This makes it difficult to change business rules, understand tier limitations, and avoid bugs.

## Solution

Create `AppConfig` class with nested modules grouping related constants. Helper methods eliminate scattered case statements.

## AppConfig Structure

```ruby
# app/models/app_config.rb
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

## Constants Audit

| Current Location | Current Name | Value | New Location |
|------------------|--------------|-------|--------------|
| `validates_episode_submission.rb` | `MAX_CHARACTERS_FREE` | 15,000 | `AppConfig::Tiers::FREE_CHARACTER_LIMIT` |
| `validates_episode_submission.rb` | `MAX_CHARACTERS_PREMIUM` | 50,000 | `AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT` |
| `checks_episode_creation_permission.rb` | `FREE_MONTHLY_LIMIT` | 2 | `AppConfig::Tiers::FREE_MONTHLY_EPISODES` |
| `voice.rb` | `STANDARD` | 4 voices | `AppConfig::Tiers::FREE_VOICES` |
| `voice.rb` | `CHIRP` | 4 voices | (merged into `UNLIMITED_VOICES`) |
| `extracts_article.rb` | `MIN_CONTENT_LENGTH` | 100 | `AppConfig::Content::MIN_LENGTH` |
| `create_paste_episode.rb` | `MINIMUM_LENGTH` | 100 | `AppConfig::Content::MIN_LENGTH` (dedupe) |
| `extracts_article.rb` | `MAX_HTML_BYTES` | 10MB | `AppConfig::Content::MAX_FETCH_BYTES` |
| `fetches_url.rb` | `MAX_CONTENT_LENGTH` | 10MB | `AppConfig::Content::MAX_FETCH_BYTES` (dedupe) |
| `fetches_url.rb` | `TIMEOUT_SECONDS` | 10 | `AppConfig::Network::TIMEOUT_SECONDS` |
| `fetches_url.rb` | `DNS_TIMEOUT_SECONDS` | 5 | `AppConfig::Network::DNS_TIMEOUT_SECONDS` |
| `processes_with_llm.rb` | `MAX_INPUT_CHARS` | 100,000 | `AppConfig::Llm::MAX_INPUT_CHARS` |
| `processes_with_llm.rb` | `MAX_TITLE_LENGTH` | 255 | `AppConfig::Llm::MAX_TITLE_LENGTH` |
| `processes_with_llm.rb` | `MAX_AUTHOR_LENGTH` | 255 | `AppConfig::Llm::MAX_AUTHOR_LENGTH` |
| `processes_with_llm.rb` | `MAX_DESCRIPTION_LENGTH` | 1,000 | `AppConfig::Llm::MAX_DESCRIPTION_LENGTH` |

## Duplicates Resolved

| Duplicate 1 | Duplicate 2 | Canonical Name |
|-------------|-------------|----------------|
| `ExtractsArticle::MIN_CONTENT_LENGTH` | `CreatePasteEpisode::MINIMUM_LENGTH` | `AppConfig::Content::MIN_LENGTH` |
| `ExtractsArticle::MAX_HTML_BYTES` | `FetchesUrl::MAX_CONTENT_LENGTH` | `AppConfig::Content::MAX_FETCH_BYTES` |

## Voice Model Refactoring

Before:
```ruby
class Voice
  STANDARD = %w[wren felix sloane archer].freeze
  CHIRP = %w[elara callum lark nash].freeze
  ALL = (STANDARD + CHIRP).freeze

  def self.for_tier(tier)
    tier.to_s == "unlimited" ? ALL : STANDARD
  end
  # ...
end
```

After:
```ruby
class Voice
  CATALOG = { ... }.freeze
  ALL = CATALOG.keys.freeze

  DEFAULT_STANDARD = "en-GB-Standard-D"
  DEFAULT_CHIRP = "en-GB-Chirp3-HD-Enceladus"

  def self.find(key)
    CATALOG[key]
  end

  def self.sample_url(key)
    # ...
  end
end
```

Tier logic moves to `AppConfig::Tiers.voices_for`.

## Migration Plan

### Step 1: Create AppConfig
- Create `app/models/app_config.rb` with all modules and constants
- Additive only, no other files change

### Step 2: Update Voice model
- Remove `STANDARD`, `CHIRP` arrays
- Remove `for_tier` method
- Change `ALL` to `CATALOG.keys`

### Step 3: Update User model
- Change `available_voices` to use `AppConfig::Tiers.voices_for(tier)`

### Step 4: Update tier-related services
- `ValidatesEpisodeSubmission` — remove constants, use `AppConfig::Tiers`
- `CalculatesMaxCharactersForUser` — simplify to delegate to `AppConfig::Tiers`
- `ChecksEpisodeCreationPermission` — use `AppConfig::Tiers::FREE_MONTHLY_EPISODES`

### Step 5: Update content validation services
- `ExtractsArticle` — use `AppConfig::Content::MIN_LENGTH` and `MAX_FETCH_BYTES`
- `CreatePasteEpisode` — remove `MINIMUM_LENGTH`, use `AppConfig::Content::MIN_LENGTH`
- `FetchesUrl` — use `AppConfig::Content::MAX_FETCH_BYTES` and `AppConfig::Network::*`

### Step 6: Update LLM service
- `ProcessesWithLlm` — use `AppConfig::Llm::*` constants

### Step 7: Run full test suite
- Verify all tests pass
- No behavior should change

## Testing Strategy

### 1. Grep verification

Before and after migration:
```bash
grep -r "MAX_\|MIN_\|LIMIT" app/
grep -r "15.000\|50.000\|100.000" app/
grep -r "10.*1024.*1024" app/
grep -rn "case.*tier\|when.*free\|when.*premium\|when.*unlimited" app/
```

### 2. Existing test suite

Run `rake test` — any failures indicate missed references.

### 3. AppConfig tests

```ruby
# test/models/app_config_test.rb
class AppConfigTest < ActiveSupport::TestCase
  test "tier character limits" do
    assert_equal 15_000, AppConfig::Tiers::FREE_CHARACTER_LIMIT
    assert_equal 50_000, AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT
    assert_nil AppConfig::Tiers.character_limit_for("unlimited")
  end

  test "voices_for returns correct arrays" do
    assert_equal 4, AppConfig::Tiers.voices_for("free").size
    assert_equal 8, AppConfig::Tiers.voices_for("unlimited").size
  end
end
```

## Risks

**Low risk** — all changes are mechanical constant moves with no logic changes.

**Watch for:**
- Typos in constant names (tests catch immediately)
- Missing a reference (grep verification + tests catch this)

## Decisions Made

- Keep `CalculatesMaxCharactersForUser` service (maintains naming consistency)
- Voice model becomes pure data catalog (no tier logic)
- Use nested modules for logical grouping (Tiers, Content, Llm, Network)
