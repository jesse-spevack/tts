# Technical Debt Audit Report

**Application:** Very Normal TTS
**Rails Version:** 8.1
**Audit Date:** December 28, 2025
**Auditor:** Architecture Review

---

## Executive Summary

This Rails application is well-architected overall, with clear service-oriented design, proper separation of concerns, and comprehensive test coverage. However, several areas of technical debt have accumulated that impact maintainability, developer onboarding, and long-term extensibility.

The following report identifies the top 5 sources of technical debt, ordered by priority, with detailed mitigation strategies.

---

## Issue #1: Fragmented Result/Outcome Pattern

**Priority:** HIGH
**Estimated Effort:** Medium (2-3 days)

### Problem Description

The codebase uses **four different patterns** for returning success/failure from services:

1. **Global `Result` class** (`app/models/result.rb`) - Used by ~30 services
2. **Global `Outcome` class** (`app/models/outcome.rb`) - Used by 1 service (`ChecksEpisodeCreationPermission`)
3. **Local `Result = Struct`** - Defined inline in 3 services:
   - `SendMagicLink::Result` (line 2)
   - `CreateUser::Result` (line 2)
   - `AuthenticateMagicLink::Result` (line 2)
4. **Custom `ValidationResult`** - `ValidatesEpisodeSubmission::ValidationResult` (line 26)

### Evidence

```ruby
# Pattern 1: Global Result (app/models/result.rb)
Result.success(episode)
Result.failure("Invalid URL")

# Pattern 2: Global Outcome (app/models/outcome.rb)
Outcome.success(nil, remaining: remaining)
Outcome.failure("Episode limit reached")

# Pattern 3: Local Struct (app/services/send_magic_link.rb:2)
Result = Struct.new(:success?, :user, keyword_init: true)
Result.new(success?: true, user: user)

# Pattern 4: Custom class (app/services/validates_episode_submission.rb:26)
ValidationResult.success(max_characters: max_characters_for_user)
```

### Impact

- **Cognitive load:** Developers must remember which return type each service uses
- **Inconsistent error handling:** Some results use `.error`, others use `.message`
- **Testing friction:** Different assertion patterns needed for different services
- **Refactoring risk:** Easy to use wrong result type when modifying services

### Mitigation Strategy

**Option A: Consolidate to Single `Result` Class (Recommended)**

1. Extend `Result` class to support optional `message` and keyword `data`:
   ```ruby
   Result.success(user, message: "User created", remaining: 5)
   ```
2. Add `flash_type` helper method for UI integration
3. Migrate all services to use unified `Result`
4. Remove `Outcome` class and local Struct definitions

**Option B: Keep Two Classes with Clear Separation**

- `Result` for internal service operations (data-focused)
- `Outcome` for controller-facing operations (message-focused)
- Document clear usage guidelines

### Pros & Cons

| Approach | Pros | Cons |
|----------|------|------|
| Option A | Single pattern to learn; simplified testing; reduced code | Migration effort; may feel overly generic |
| Option B | Semantic clarity; minimal migration | Two patterns to maintain; boundary ambiguity |

### Files Affected

- `app/models/result.rb`
- `app/models/outcome.rb`
- `app/services/send_magic_link.rb`
- `app/services/create_user.rb`
- `app/services/authenticate_magic_link.rb`
- `app/services/validates_episode_submission.rb`
- `app/services/checks_episode_creation_permission.rb`
- All consuming controllers and tests (~15 files)

---

## Issue #2: Inconsistent Service Naming Conventions

**Priority:** HIGH
**Estimated Effort:** Medium-Large (3-4 days)

### Problem Description

Services use **two conflicting naming conventions** without clear semantic distinction:

| Convention | Example Services | Count |
|------------|-----------------|-------|
| **Imperative** (`VerbNoun`) | `CreateUser`, `GenerateAuthToken`, `DeleteEpisode`, `SendMagicLink` | ~18 |
| **Third-person singular** (`VerbsNoun`) | `ValidatesUrl`, `NormalizesUrl`, `GeneratesContentPreview`, `CalculatesMaxCharactersForUser` | ~12 |

### Evidence

```ruby
# Imperative style
CreateUrlEpisode.call(podcast:, user:, url:)
GenerateRssFeed.call(podcast:)
DeleteEpisode.call(episode:)

# Third-person singular style
ValidatesUrl.valid?(url)
NormalizesUrl.call(url:)
GeneratesEpisodeAudioUrl.call(episode)
CalculatesMaxCharactersForUser.call(user:)
```

### Impact

- **Unpredictable naming:** Cannot guess service name from action
- **Autocomplete friction:** IDE suggestions harder to filter
- **Onboarding confusion:** New developers unsure which convention to follow
- **Model delegation inconsistency:** `episode.audio_url` calls `GeneratesEpisodeAudioUrl` but `episode.download_url` calls `GenerateEpisodeDownloadUrl`

### Mitigation Strategy

**Recommended: Standardize on Imperative Naming**

The Rails community convention favors imperative naming for service objects (matching ActiveJob, Action Mailer patterns).

**Rename pattern:**
- `ValidatesUrl` → `ValidateUrl` (or make module method on Episode)
- `NormalizesUrl` → `NormalizeUrl`
- `GeneratesEpisodeAudioUrl` → `GenerateEpisodeAudioUrl`
- `GeneratesContentPreview` → `GenerateContentPreview`
- `CalculatesMaxCharactersForUser` → move to `AppConfig::Tiers.character_limit_for(user.tier)` (already exists!)
- `ChecksEpisodeCreationPermission` → `CheckEpisodeCreationPermission`

### Special Cases

Some services are better as **validators or query objects**:
- `ValidatesUrl` → Could become `UrlValidator` or module method
- `ValidatesEpisodeSubmission` → Could become `EpisodeSubmissionValidator`

### Pros & Cons

| Approach | Pros | Cons |
|----------|------|------|
| Standardize imperative | Matches Rails conventions; predictable | Large rename effort; git history noise |
| Keep mixed (document) | No code changes | Perpetuates confusion; no single source of truth |

### Files Affected (Renames)

```
app/services/validates_url.rb → validate_url.rb
app/services/normalizes_url.rb → normalize_url.rb
app/services/generates_episode_audio_url.rb → generate_episode_audio_url.rb
app/services/generates_podcast_feed_url.rb → generate_podcast_feed_url.rb
app/services/generates_content_preview.rb → generate_content_preview.rb
app/services/calculates_max_characters_for_user.rb → (delete, use AppConfig directly)
app/services/checks_episode_creation_permission.rb → check_episode_creation_permission.rb
+ corresponding test files
+ all call sites (~25 files)
```

---

## Issue #3: GCS Configuration Duplication

**Priority:** MEDIUM
**Estimated Effort:** Small (0.5-1 day)

### Problem Description

The GCS bucket name pattern `ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")` is duplicated **11 times** across 7 files, along with URL construction logic.

### Evidence

```ruby
# app/services/cloud_storage.rb:5
@bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")

# app/services/generate_rss_feed.rb:54 (and again at line 104!)
bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")

# app/services/generates_episode_audio_url.rb:15
bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")

# app/services/generates_podcast_feed_url.rb:15
bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")

# app/services/generate_episode_download_url.rb:37
ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")

# app/models/voice.rb:21
bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
```

**URL pattern also duplicated:**
```ruby
"https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/..."
```

### Impact

- **Maintenance risk:** Changing bucket name requires 7+ file edits
- **Bug potential:** Easy to introduce typo in one location
- **Default value drift:** Different defaults could be introduced
- **Testing complexity:** Each file needs bucket stubbing

### Mitigation Strategy

**Add GCS configuration to `AppConfig`:**

```ruby
# app/models/app_config.rb
module Storage
  BUCKET = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
  BASE_URL = "https://storage.googleapis.com/#{BUCKET}"

  def self.podcast_path(podcast_id)
    "#{BASE_URL}/podcasts/#{podcast_id}"
  end

  def self.episode_url(podcast_id, gcs_episode_id)
    "#{podcast_path(podcast_id)}/episodes/#{gcs_episode_id}.mp3"
  end

  def self.feed_url(podcast_id)
    "#{podcast_path(podcast_id)}/feed.xml"
  end

  def self.voice_sample_url(voice_key)
    "#{BASE_URL}/voices/#{voice_key}.mp3"
  end
end
```

### Pros & Cons

| Approach | Pros | Cons |
|----------|------|------|
| Centralize in AppConfig | Single source of truth; easy testing; clear documentation | Small refactor effort |
| Leave as-is | No code changes | Continued duplication; maintenance risk |

### Files Affected

- `app/models/app_config.rb` (add Storage module)
- `app/services/cloud_storage.rb`
- `app/services/generate_rss_feed.rb`
- `app/services/generates_episode_audio_url.rb`
- `app/services/generates_podcast_feed_url.rb`
- `app/services/generate_episode_download_url.rb`
- `app/models/voice.rb`
- Test files using bucket name (~4 files)

---

## Issue #4: Duplicated Processing Infrastructure

**Priority:** MEDIUM
**Estimated Effort:** Small-Medium (1-2 days)

### Problem Description

Episode processing services share significant duplicated code:

#### 4a. Duplicated `ProcessingError` Exception

```ruby
# app/services/process_url_episode.rb:112
class ProcessingError < StandardError; end

# app/services/process_paste_episode.rb:76
class ProcessingError < StandardError; end
```

#### 4b. Nearly Identical Job Boilerplate

```ruby
# app/jobs/process_url_episode_job.rb
def perform(episode_id)
  Rails.logger.info "event=process_url_episode_job_started episode_id=#{episode_id}"
  episode = Episode.find(episode_id)
  ProcessUrlEpisode.call(episode: episode)
  Rails.logger.info "event=process_url_episode_job_completed episode_id=#{episode_id}"
rescue StandardError => e
  Rails.logger.error "event=process_url_episode_job_failed episode_id=#{episode_id}..."
  raise
end

# app/jobs/process_paste_episode_job.rb (nearly identical)
# app/jobs/process_file_episode_job.rb (nearly identical)
```

#### 4c. Duplicated `fail_episode` Method

```ruby
# process_url_episode.rb:106
def fail_episode(error_message)
  episode.update!(status: :failed, error_message: error_message)
  log_warn "episode_marked_failed", error: error_message
end

# process_paste_episode.rb:71 (identical)
# process_file_episode.rb:38 (similar)
```

#### 4d. Inconsistent Job Argument Patterns

```ruby
# Takes episode_id (correct for async)
ProcessUrlEpisodeJob.perform_later(episode.id)

# Takes full Episode object (risky - object may change before job runs)
DeleteEpisodeJob.perform_later(@episode)
```

### Impact

- **DRY violation:** Same code maintained in multiple places
- **Bug divergence:** Fix in one place may miss others
- **Inconsistency risk:** Behavior drift over time
- **Serialization issues:** Passing objects to jobs can cause stale data

### Mitigation Strategy

**Step 1: Extract shared exception**
```ruby
# app/services/concerns/episode_processing.rb
module EpisodeProcessing
  class ProcessingError < StandardError; end

  extend ActiveSupport::Concern
  include EpisodeLogging

  included do
    attr_reader :episode, :user
  end

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    log_warn "episode_marked_failed", error: error_message
  end
end
```

**Step 2: Create base job with logging concern**
```ruby
# app/jobs/concerns/episode_job_logging.rb
module EpisodeJobLogging
  extend ActiveSupport::Concern

  def perform_with_logging(episode_id, service_class)
    Rails.logger.info "event=#{job_event_name}_started episode_id=#{episode_id}"
    episode = Episode.find(episode_id)
    service_class.call(episode: episode)
    Rails.logger.info "event=#{job_event_name}_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=#{job_event_name}_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
```

**Step 3: Fix DeleteEpisodeJob argument**
```ruby
# Change from:
DeleteEpisodeJob.perform_later(@episode)
# To:
DeleteEpisodeJob.perform_later(@episode.id)
```

### Pros & Cons

| Approach | Pros | Cons |
|----------|------|------|
| Extract concerns | DRY; consistent behavior; easier testing | Indirection; concern dependency chain |
| Leave duplicated | Explicit code in each file | Maintenance burden; divergence risk |

### Files Affected

- `app/services/concerns/episode_processing.rb` (new)
- `app/services/process_url_episode.rb`
- `app/services/process_paste_episode.rb`
- `app/services/process_file_episode.rb`
- `app/jobs/concerns/episode_job_logging.rb` (new)
- `app/jobs/process_url_episode_job.rb`
- `app/jobs/process_paste_episode_job.rb`
- `app/jobs/process_file_episode_job.rb`
- `app/jobs/delete_episode_job.rb`
- `app/controllers/episodes_controller.rb` (job call site)

---

## Issue #5: Obsolete/Dead Code

**Priority:** LOW
**Estimated Effort:** Small (0.5 day)

### Problem Description

Several pieces of code appear unused or marked as deprecated:

#### 5a. Deprecated Helper Method

```ruby
# app/helpers/episodes_helper.rb:41-55
# Keep old method for backwards compatibility during migration
def status_class(status)
  case status
  when "pending"
    "bg-yellow-100 text-yellow-800"
  # ... Tailwind classes not used in current views
```

#### 5b. Redundant Service

```ruby
# app/services/calculates_max_characters_for_user.rb
class CalculatesMaxCharactersForUser
  def self.call(user:)
    AppConfig::Tiers.character_limit_for(user.tier)
  end
end
```

This is a one-line wrapper around `AppConfig::Tiers.character_limit_for` which already exists and is more semantically clear.

#### 5c. Commented-Out Job Configuration

```ruby
# app/jobs/application_job.rb:2-6
# Automatically retry jobs that encountered a deadlock
# retry_on ActiveRecord::Deadlocked

# Most jobs are safe to ignore if the underlying records are no longer available
# discard_on ActiveJob::DeserializationError
```

### Impact

- **Confusion:** Developers unsure if code is intentionally unused
- **Maintenance:** Dead code still needs to pass linting/tests
- **Bundle size:** Unnecessary code loaded into memory

### Mitigation Strategy

1. **Remove `status_class` helper** - Verify no views use it, then delete
2. **Inline or remove `CalculatesMaxCharactersForUser`** - Replace 6 call sites with `AppConfig::Tiers.character_limit_for(user.tier)`
3. **Delete or enable job configuration** - Either enable retry/discard or remove comments

### Pros & Cons

| Approach | Pros | Cons |
|----------|------|------|
| Remove dead code | Cleaner codebase; less confusion | Small risk of missing usage |
| Keep with TODO | No risk | Perpetuates clutter |

### Files Affected

- `app/helpers/episodes_helper.rb`
- `app/services/calculates_max_characters_for_user.rb`
- `app/jobs/application_job.rb`
- Call sites for `CalculatesMaxCharactersForUser` (~6 files)

---

## Summary & Prioritization Matrix

| Issue | Priority | Effort | Impact | Recommendation |
|-------|----------|--------|--------|----------------|
| #1 Result/Outcome fragmentation | HIGH | Medium | High | Address in next sprint |
| #2 Service naming inconsistency | HIGH | Medium-Large | High | Plan multi-phase migration |
| #3 GCS config duplication | MEDIUM | Small | Medium | Quick win - do first |
| #4 Processing infrastructure duplication | MEDIUM | Small-Medium | Medium | Combine with #1 |
| #5 Dead/obsolete code | LOW | Small | Low | Opportunistic cleanup |

### Recommended Approach Order

1. **Start with Issue #3** (GCS config) - Quick win, low risk, immediate benefit
2. **Address Issue #1** (Result consolidation) - High impact, enables cleaner patterns
3. **Tackle Issue #4** (Processing duplication) - Natural extension of #1
4. **Plan Issue #2** (Naming) - Larger effort, consider phased approach
5. **Opportunistically handle Issue #5** - During related work

---

## Appendix: Files Audited

### Models (8)
- `app/models/app_config.rb`
- `app/models/episode.rb`
- `app/models/outcome.rb`
- `app/models/podcast.rb`
- `app/models/result.rb`
- `app/models/user.rb`
- `app/models/voice.rb`
- (+ Episode/Llm/Sent/Page usage models)

### Services (47)
- All files in `app/services/` and `app/services/tts/`

### Controllers (8)
- `app/controllers/application_controller.rb`
- `app/controllers/episodes_controller.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/settings_controller.rb`
- `app/controllers/pages_controller.rb`
- `app/controllers/admin/analytics_controller.rb`
- `app/controllers/api/internal/base_controller.rb`
- `app/controllers/api/internal/episodes_controller.rb`

### Jobs (5)
- All files in `app/jobs/`

### Concerns (3)
- `app/controllers/concerns/authentication.rb`
- `app/controllers/concerns/trackable.rb`
- `app/services/concerns/episode_logging.rb`

### Test Coverage
- 43 service tests
- 6 controller tests
- Model and integration tests

---

*Report generated for architectural review purposes. All recommendations should be validated against current business priorities and team capacity.*
