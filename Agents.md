# Agent Guide: Very Normal TTS Codebase

This document provides comprehensive guidance for AI coding agents working with the Very Normal TTS codebase. It covers architecture patterns, naming conventions, code locations, and development workflows.

## Quick Start for Agents

### Understanding the Application

Very Normal TTS is a **Ruby on Rails 8.1** application that converts text content into podcast episodes. Users can:
1. Submit a URL → App fetches and extracts article content
2. Paste text → App processes the text directly
3. Upload a file → App uses content as-is

All three paths lead to audio synthesis via Google Cloud TTS and delivery via RSS feed.

### Key Commands

```bash
# Run tests (use before committing)
bin/rails test

# Run specific test file
bin/rails test test/services/process_url_episode_test.rb

# Lint code
bin/rubocop

# Start development server
bin/dev
```

## Architecture Overview

### Request Lifecycle

```
Controller (sync)
     │
     ├── Creates Episode (status: processing)
     ├── Enqueues background job
     └── Redirects to episodes_path with flash

Background Job (async)
     │
     ├── Process content (URL/Paste/File specific)
     ├── Generate audio via TTS API
     ├── Upload to GCS
     ├── Regenerate RSS feed
     └── Update Episode (status: complete)

Turbo Stream broadcasts status change to connected clients
```

### Core Domain Models

Located in `app/models/`:

| Model | File | Purpose | Key Fields |
|-------|------|---------|------------|
| `User` | `user.rb` | User accounts | `email_address`, `tier`, `voice_preference`, `admin` |
| `Podcast` | `podcast.rb` | Episode container | `podcast_id` (unique GCS path identifier) |
| `Episode` | `episode.rb` | Audio episode | `status`, `source_type`, `source_url`, `source_text`, `gcs_episode_id` |
| `PodcastMembership` | `podcast_membership.rb` | User-Podcast join | `user_id`, `podcast_id` |
| `Session` | `session.rb` | Auth session | `user_id`, `ip_address`, `user_agent` |
| `EpisodeUsage` | `episode_usage.rb` | Monthly usage tracking | `user_id`, `period_start`, `episode_count` |
| `LlmUsage` | `llm_usage.rb` | LLM cost tracking | `episode_id`, `input_tokens`, `output_tokens`, `cost_cents` |
| `SentMessage` | `sent_message.rb` | Prevents duplicate emails | `user_id`, `message_type` |
| `PageView` | `page_view.rb` | Anonymous analytics | `path`, `visitor_hash`, `referrer_host` |

### Non-ActiveRecord Models

| Class | File | Purpose |
|-------|------|---------|
| `Result` | `result.rb` | Success/failure wrapper with data |
| `Outcome` | `outcome.rb` | Success/failure wrapper with message and optional data |
| `AppConfig` | `app_config.rb` | Centralized configuration constants |
| `Voice` | `voice.rb` | Voice catalog and configuration |
| `Current` | `current.rb` | Thread-local session/user access |

### Episode Status Enum

```ruby
enum :status, { pending: "pending", processing: "processing", complete: "complete", failed: "failed" }
```

### Episode Source Type Enum

```ruby
enum :source_type, { file: 0, url: 1, paste: 2 }
```

### User Tier Enum

```ruby
enum :tier, { free: 0, premium: 1, unlimited: 2 }
```

## Service Object Patterns

### Location
All service objects are in `app/services/`. Follow these conventions:

### Naming Conventions

| Pattern | Convention | Example |
|---------|------------|---------|
| Creates something | `Creates*` | `CreatesUrlEpisode`, `CreatesUser` |
| Processes something | `Processes*` | `ProcessesUrlEpisode`, `ProcessesPasteEpisode` |
| Validates | `Validates*` | `ValidatesUrl`, `ValidatesEpisodeSubmission` |
| Generates | `Generates*` | `GeneratesEpisodeAudio`, `GeneratesContentPreview` |
| Builds | `Builds*` | `BuildsEpisodeWrapper`, `BuildsUrlProcessingPrompt` |
| Checks permission | `Checks*` | `ChecksEpisodeCreationPermission` |
| Calculates | `Calculates*` | `CalculatesMaxCharactersForUser` |
| Records | `Records*` | `RecordsEpisodeUsage`, `RecordsLlmUsage` |
| Other verbs | `Verb*` | `FetchesUrl`, `ExtractsArticle`, `StripsMarkdown` |

### Service Object Structure

```ruby
# frozen_string_literal: true

class ServiceName
  def self.call(**args)
    new(**args).call
  end

  def initialize(**args)
    @arg1 = arg1
    @arg2 = arg2
  end

  def call
    # Business logic here
    # Return Result or Outcome object
  end

  private

  attr_reader :arg1, :arg2
end
```

### Result Pattern

**Use `Result`** when the service returns data on success:

```ruby
# In service
Result.success(episode)      # Success with data
Result.failure("Error msg")  # Failure with error string

# Calling code
result = CreatesUrlEpisode.call(podcast: podcast, user: user, url: url)
if result.success?
  episode = result.data
else
  error_message = result.error
end
```

**Use `Outcome`** for yes/no operations with optional metadata:

```ruby
# In service
Outcome.success                           # Simple success
Outcome.success(nil, remaining: 5)        # Success with optional data
Outcome.failure("Limit reached")          # Failure with message

# Calling code
outcome = ChecksEpisodeCreationPermission.call(user: user)
if outcome.success?
  remaining = outcome.data[:remaining]  # Optional data access
else
  flash[:alert] = outcome.message
end
```

## Controller Patterns

### Location
`app/controllers/`

### Authentication

```ruby
class SomeController < ApplicationController
  before_action :require_authentication  # Default - requires login

  # Or for public access:
  allow_unauthenticated_access only: [:show, :index]
end
```

Access current user via:
```ruby
Current.user              # Current user or nil
Current.session           # Current session
Current.user_admin?       # Check admin status
authenticated?            # Helper for views
```

### Episode Creation Flow

The `EpisodesController#create` action routes to three private methods based on params:
- `create_from_url` - when `params[:url]` present
- `create_from_paste` - when `params[:text]` present
- `create_from_file` - default fallback

Each calls the appropriate `Create*Episode` service and handles the result.

### Admin Protection

```ruby
# In controller
before_action :require_admin

private

def require_admin
  head :not_found unless Current.user_admin?
end
```

## Background Jobs

### Location
`app/jobs/`

### Job Naming
- `Processes*EpisodeJob` - Processes episode content and generates audio
- `DeleteEpisodeJob` - Soft deletes episode and cleans up GCS files

### Job Structure

```ruby
class ProcessesUrlEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    Rails.logger.info "event=processes_url_episode_job_started episode_id=#{episode_id}"

    episode = Episode.find(episode_id)
    ProcessesUrlEpisode.call(episode: episode)

    Rails.logger.info "event=process_url_episode_job_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=process_url_episode_job_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
```

### Queue Configuration
Jobs run via Solid Queue. In production, `SOLID_QUEUE_IN_PUMA=true` runs the queue in-process with Puma.

## TTS Subsystem

### Location
`app/services/tts/` and `app/services/synthesizes_audio.rb`

### Components

| Class | Purpose |
|-------|---------|
| `Tts::Config` | TTS configuration (voice, rate, pitch, limits) |
| `Tts::ApiClient` | Google Cloud TTS API wrapper with retry logic |
| `Tts::TextChunker` | Splits text at byte limit boundaries |
| `Tts::ChunkedSynthesizer` | Parallel chunk processing for long text |
| `SynthesizesAudio` | Main entry point, orchestrates TTS flow |

### Voice Configuration

```ruby
# Available voices (app/models/voice.rb)
Voice::CATALOG = {
  "wren"   => { name: "Wren",   accent: "British",  gender: "Female", google_voice: "en-GB-Standard-C" },
  "felix"  => { name: "Felix",  accent: "British",  gender: "Male",   google_voice: "en-GB-Standard-D" },
  # ... more voices
}

# Tier-based voice access (app/models/app_config.rb)
AppConfig::Tiers::FREE_VOICES     = %w[wren felix sloane archer]
AppConfig::Tiers::UNLIMITED_VOICES = FREE_VOICES + %w[elara callum lark nash]
```

## Frontend Architecture

### Hotwire Stack

- **Turbo Drive**: SPA-like navigation
- **Turbo Frames**: Partial page updates
- **Turbo Streams**: Real-time updates (episode status changes)
- **Stimulus**: JavaScript controllers

### Stimulus Controllers

Located in `app/javascript/controllers/`:

| Controller | Purpose | Key Actions |
|------------|---------|-------------|
| `clipboard_controller.js` | Copy to clipboard | `copy()` |
| `tab_switch_controller.js` | Tab navigation | `switch()` |
| `theme_controller.js` | Dark/light mode toggle | `toggle()`, `loadTheme()` |
| `file_upload_controller.js` | File drag-and-drop | `handleDrop()` |
| `audio_preview_controller.js` | Voice sample playback | `toggle()`, `restart()` |
| `mobile_menu_controller.js` | Mobile nav menu | `toggle()`, `close()` |
| `auto_dismiss_controller.js` | Flash message auto-hide | `dismiss()` |

### Turbo Streams

Episode cards broadcast status changes:

```ruby
# app/models/episode.rb
after_update_commit :broadcast_status_change, if: :saved_change_to_status?

def broadcast_status_change
  broadcast_replace_to(
    "podcast_#{podcast_id}_episodes",
    target: self,
    partial: "episodes/episode_card",
    locals: { episode: self }
  )
end
```

Subscribe in view:
```erb
<%= turbo_stream_from "podcast_#{@podcast.id}_episodes" %>
```

### CSS Architecture

- **Tailwind CSS**: Utility-first styling
- **CSS Variables**: Theme colors via `--color-*` custom properties
- **Dark Mode**: `.dark` class on `<html>` element

## Testing Patterns

### Location
`test/` directory mirrors `app/` structure

### Test Helpers

```ruby
# Sign in for controller/integration tests
# test/test_helpers/session_test_helper.rb
sign_in_as(users(:one))
sign_out
```

### Mocking with Mocktail

```ruby
# test/test_helper.rb includes Mocktail::DSL
# Example service mock:
synthesizer = Mocktail.of(SynthesizesAudio)
stubs { synthesizer.call(any, voice: any) }.with { "audio content" }
```

### WebMock for HTTP

```ruby
# External requests are blocked by default
stub_request(:get, "https://example.com/article")
  .to_return(status: 200, body: html_content)
```

### Fixture Conventions

```yaml
# test/fixtures/users.yml
free_user:
  email_address: free@example.com
  tier: 0  # free

premium_user:
  email_address: premium@example.com
  tier: 1  # premium
```

Reference in tests: `users(:free_user)`

## Configuration Constants

### Location
`app/models/app_config.rb`

### Available Constants

```ruby
# Tier limits
AppConfig::Tiers::FREE_CHARACTER_LIMIT    # 15,000
AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT # 50,000
AppConfig::Tiers::FREE_MONTHLY_EPISODES   # 2

# Content limits
AppConfig::Content::MIN_LENGTH            # 100
AppConfig::Content::MAX_FETCH_BYTES       # 10MB

# LLM limits
AppConfig::Llm::MAX_INPUT_CHARS           # 100,000
AppConfig::Llm::MAX_TITLE_LENGTH          # 255
AppConfig::Llm::MAX_AUTHOR_LENGTH         # 255
AppConfig::Llm::MAX_DESCRIPTION_LENGTH    # 1,000

# Network timeouts
AppConfig::Network::TIMEOUT_SECONDS       # 10
AppConfig::Network::DNS_TIMEOUT_SECONDS   # 5
```

## Logging Conventions

### Structured Logging

Use `event=` key-value format:

```ruby
Rails.logger.info "event=episode_created episode_id=#{episode.id} source_type=url"
Rails.logger.warn "event=rate_limit_exceeded user_id=#{user.id}"
Rails.logger.error "event=tts_api_error error=#{e.class} message=#{e.message}"
```

### Episode Logging Concern

`app/services/concerns/episode_logging.rb` provides:

```ruby
include EpisodeLogging

log_info "process_started", url: episode.source_url
log_warn "extraction_failed", error: result.error
log_error "unexpected_error", error: e.class, message: e.message
```

### Privacy-Safe Email Logging

```ruby
LoggingHelper.mask_email("user@example.com")  # => "us***@example.com"
```

## Routes Reference

```ruby
# Core routes
root                    # pages#home
episodes                # episodes#index
new_episode             # episodes#new
episode(id)             # episodes#show (public, complete episodes only)

# Authentication
auth                    # sessions#new (with token param for magic link)
session                 # sessions#create/destroy

# Settings
settings                # settings#show/update

# Admin
admin_analytics         # admin/analytics#show

# API (internal)
api_internal_episode    # api/internal/episodes#update

# Static pages
terms                   # pages#terms
how_it_sounds           # pages#how_it_sounds
help_add_rss_feed       # pages#add_rss_feed
```

## Common Development Tasks

### Adding a New Service

1. Create `app/services/new_service.rb`
2. Follow service object structure (see patterns above)
3. Create `test/services/new_service_test.rb`
4. Run `bin/rails test test/services/new_service_test.rb`

### Adding a New Stimulus Controller

1. Create `app/javascript/controllers/new_controller.js`
2. Controller auto-registers via Import Maps
3. Use in views: `data-controller="new"`

### Modifying Episode Processing

1. Processing services: `app/services/process_*_episode.rb`
2. Background jobs: `app/jobs/process_*_episode_job.rb`
3. Creation services: `app/services/create_*_episode.rb`

### Adding New Tier Features

1. Update `AppConfig::Tiers` constants
2. Update `User` model tier enum if adding new tier
3. Update `Voice::CATALOG` for voice restrictions
4. Update permission checks in `ChecksEpisodeCreationPermission`

### Database Migrations

```bash
# Generate migration
bin/rails generate migration AddFieldToEpisodes field:string

# Run migrations
bin/rails db:migrate

# Rollback
bin/rails db:rollback
```

## Security Considerations

### SSRF Protection

`FetchesUrl` blocks private IP ranges:
- `127.0.0.0/8` (loopback)
- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` (private)
- `169.254.0.0/16` (link-local/cloud metadata)
- IPv6 equivalents

### Input Validation

- URL validation: `ValidatesUrl`
- Content length: Model validations + tier-based limits
- Email format: URI::MailTo::EMAIL_REGEXP

### Authentication

- Magic link tokens: BCrypt-hashed, 30-minute expiration
- Sessions: Signed cookies, httponly
- Rate limiting: 10 magic link requests per 3 minutes

### API Security

Internal API (`/api/internal/episodes`) requires `X-Generator-Secret` header matching `GENERATOR_CALLBACK_SECRET` env var.

## File Reference Quick Lookup

| Need to... | Look in... |
|------------|------------|
| Change episode processing | `app/services/process_*_episode.rb` |
| Modify TTS synthesis | `app/services/tts/`, `app/services/synthesizes_audio.rb` |
| Update tier limits | `app/models/app_config.rb` |
| Add voice options | `app/models/voice.rb` |
| Change auth flow | `app/services/send_magic_link.rb`, `app/services/authenticate_magic_link.rb` |
| Update email templates | `app/views/sessions_mailer/`, `app/views/user_mailer/` |
| Modify episode UI | `app/views/episodes/` |
| Add controller logic | `app/controllers/` |
| Update routing | `config/routes.rb` |
| Change deployment | `config/deploy.yml` |
| Add background job | `app/jobs/` |
| Write tests | `test/` (mirrors `app/` structure) |

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
