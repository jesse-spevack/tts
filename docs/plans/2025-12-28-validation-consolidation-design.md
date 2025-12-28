# Validation Consolidation Design

## Problem

Content validation logic is scattered across 4 services:
- `CreatePasteEpisode` - presence, min length, tier limit
- `CreateFileEpisode` - presence, tier limit (missing min length - bug)
- `ProcessUrlEpisode` - tier limit after extraction
- `ExtractsArticle` - min length for extraction quality

This causes duplicate code, inconsistent error messages, and weaker data integrity (validation can be bypassed by creating episodes directly).

## Goals (Prioritized)

1. **Data integrity** - Impossible to create invalid episodes, even via console
2. **Code maintainability** - Single source of truth for validation logic
3. **Test simplicity** - Test validation in one place

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to validate | Episode model | Only place that can't be bypassed |
| Tier limit access | Model calls `CalculatesMaxCharactersForUser` | Episode already has user association |
| URL episodes | Keep validation in ProcessUrlEpisode | Content unknown at creation time |
| Error messages | Standardize on "Content" | Simpler; UI context provides specificity |
| Min length for files | Add it (bug fix) | Should have been there originally |

## Model Validations

```ruby
# app/models/episode.rb

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

private

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

## Simplified Services

### CreatePasteEpisode (after)

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

### CreateFileEpisode (after)

Same pattern - remove validation methods, use `create` instead of `create!`, check `persisted?`.

### ProcessUrlEpisode

Unchanged except standardized error message:

```ruby
def check_character_limit
  max_chars = CalculatesMaxCharactersForUser.call(user: user)
  return unless max_chars && @extract_result.data.character_count > max_chars

  raise ProcessingError,
    "Content exceeds your plan's #{max_chars.to_fs(:delimited)} character limit " \
    "(#{@extract_result.data.character_count.to_fs(:delimited)} characters)"
end
```

### ExtractsArticle

Unchanged - its validation checks extraction quality, not episode validity.

## Locale Translation

```yaml
# config/locales/en.yml
en:
  activerecord:
    attributes:
      episode:
        source_text: "Content"
```

## Migration Plan

| Step | Change | Risk |
|------|--------|------|
| 1 | Add locale translation | None |
| 2 | Add model validations | Low - services still validate |
| 3 | Update CreatePasteEpisode | Medium - test thoroughly |
| 4 | Update CreateFileEpisode | Medium - also fixes min-length bug |
| 5 | Standardize ProcessUrlEpisode message | Low |
| 6 | Update tests | None |
| 7 | Remove dead code | None |

Steps 1-2 can deploy first as a safety net before removing service validation.

## Files to Modify

| File | Change |
|------|--------|
| `app/models/episode.rb` | Add validations |
| `config/locales/en.yml` | Add translation |
| `app/services/create_paste_episode.rb` | Remove validation (~20 lines) |
| `app/services/create_file_episode.rb` | Remove validation (~15 lines) |
| `app/services/process_url_episode.rb` | Update error message |
| `test/models/episode_test.rb` | Add validation tests |
| `test/services/create_paste_episode_test.rb` | Simplify |
| `test/services/create_file_episode_test.rb` | Simplify |

## Testing Strategy

### Model Tests (new)

```ruby
test "paste episode requires source_text" do
  episode = build(:episode, source_type: :paste, source_text: nil)
  assert_not episode.valid?
  assert_includes episode.errors[:source_text], "cannot be empty"
end

test "paste episode requires minimum length" do
  episode = build(:episode, source_type: :paste, source_text: "short")
  assert_not episode.valid?
  assert_includes episode.errors[:source_text], "must be at least 100 characters"
end

test "paste episode validates tier limit" do
  user = create(:user, tier: :free)
  episode = build(:episode, user: user, source_type: :paste,
                  source_text: "x" * 20_000)
  assert_not episode.valid?
  assert episode.errors[:source_text].first.include?("exceeds your plan's")
end

test "url episode skips source_text validation" do
  episode = build(:episode, source_type: :url, source_text: nil)
  assert episode.valid?
end
```

### Service Tests

- Remove redundant validation tests
- Keep integration tests verifying Result.failure for invalid input
- Focus on job enqueue behavior

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Model validation breaks existing tests | Medium | Run tests after Step 2 |
| Error message changes affect UI | Low | Intentional; review in PR |
| File min-length rejects valid uploads | Low | 100 chars is very short |
| Console scripts bypass validation | Low | Intentional improvement |

## Out of Scope

- Changing the Result pattern
- Modifying controller error handling
- URL episode content storage on model
