# Architecture Analysis: Generator & Hub

## Executive Summary

The TTS application is split between two components:
- **Hub**: Rails 8.1 app (Kamal → GCP VM) - handles web UI, users, content extraction
- **Generator**: Sinatra app (Cloud Run) - handles TTS conversion, RSS generation

**Recommendation**: Merge the generator into the hub. The current split adds complexity without providing meaningful benefits at current scale, and consolidation aligns with your goals of reducing complexity, improving velocity, and future-proofing.

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Hub (Rails + Kamal)                      │
│  GCP VM 34.106.61.4 • Port 80 (HTTPS)                           │
│  • Web UI, Auth, Content Extraction, LLM, SQLite                │
└────────────────────────────┬────────────────────────────────────┘
                             │ Cloud Tasks + GCS
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│               Generator (Sinatra + Cloud Run)                   │
│  Serverless • 2Gi RAM • 4 CPUs                                  │
│  • TTS Processing, RSS Generation, GCS Upload                   │
└─────────────────────────────────────────────────────────────────┘
```

### Dependencies Between Components

| Dependency Type | Direction | Mechanism |
|-----------------|-----------|-----------|
| Task dispatch | Hub → Generator | Cloud Tasks HTTP POST |
| Content transfer | Hub → Generator | GCS staging files |
| Status callback | Generator → Hub | HTTP PATCH |
| Shared storage | Both | GCS bucket (podcast_id scoped) |
| Secret sync | Both | Must match callback secrets |

### Key Files

**Generator (root directory):**
- `api.rb` - Sinatra endpoints (/publish, /process, /health)
- `lib/episode_processor.rb` - Main processing orchestrator
- `lib/tts/` - TTS conversion library
- `lib/hub_callback_client.rb` - Notifies hub of completion
- `Dockerfile` - Cloud Run container

**Hub (hub/ directory):**
- `app/services/submit_episode_for_processing.rb` - Dispatches to generator
- `app/services/cloud_tasks_enqueuer.rb` - Creates Cloud Tasks
- `app/controllers/api/internal/episodes_controller.rb` - Receives callbacks
- `config/deploy.yml` - Kamal deployment

---

## Benefits of Current Split Architecture

### 1. Independent Scaling
Cloud Run auto-scales the generator independently of the hub. TTS processing is CPU-intensive and could theoretically benefit from elastic scaling.

**Reality check**: With no active users, this benefit is theoretical. Cloud Run min-instances is 0, so the generator cold-starts on each request.

### 2. Fault Isolation
If the generator crashes, the hub continues working. Users can still submit content; processing just queues up.

**Reality check**: With SQLite and single-server hub deployment, the hub is already a single point of failure. True fault isolation would require more investment.

### 3. Technology Flexibility
The generator could be rewritten in a different language (Go, Rust) for performance without affecting the hub.

**Reality check**: Ruby with Google Cloud TTS API is not a bottleneck. The TTS API itself is the slow part, not local processing.

### 4. Simpler Processing Code
The generator's Sinatra app is simpler than Rails. Processing logic doesn't need Rails overhead.

**Reality check**: Rails overhead is negligible for background jobs. Solid Queue + Active Job provide a clean abstraction.

### 5. Deployment Independence
Can deploy generator without touching hub and vice versa.

**Reality check**: True, but also means two deployment systems to maintain (Cloud Run + Kamal).

---

## Problems with Current Split Architecture

### 1. Complexity Overhead
**Duplicated patterns:**
- Both have `gcs_uploader.rb` (different implementations)
- Both have `cloud_tasks_enqueuer.rb`
- Both handle the same environment variables

**Mental overhead:** Understanding the full system requires reading two codebases with different conventions.

### 2. Debugging Difficulty
Issues can span both systems:
- Is the episode stuck because Hub didn't dispatch, Cloud Tasks failed, Generator crashed, or callback failed?
- Logs are in different places (Cloud Run logs vs VM logs)
- No unified tracing

### 3. Secret Management Complexity
Secrets that must stay synchronized:
- `HUB_CALLBACK_SECRET` (generator) == `GENERATOR_CALLBACK_SECRET` (hub)
- `GOOGLE_CLOUD_BUCKET` in both
- `GOOGLE_CLOUD_PROJECT` in both

**Risk:** Misconfigured secrets cause silent failures.

### 4. Development Friction
To test the full flow locally:
- Run Sinatra on one port
- Run Rails on another
- Configure Cloud Tasks emulator or mock
- Match environment variables between both

### 5. Deployment Complexity
Two completely different deployment systems:
- **Generator:** `gcloud run deploy` via GitHub Actions
- **Hub:** Kamal with Docker, secrets, and SSH

### 6. Cold Start Latency
Cloud Run with min-instances=0 means every request hits cold start (~3-5 seconds) before TTS processing even begins.

### 7. Unnecessary Indirection
The communication flow:
```
Hub → GCS upload → Cloud Tasks → Generator → GCS download → Process → GCS upload → HTTP callback → Hub
```

With a merged system:
```
Hub → Background job → Process → GCS upload
```

### 8. RSS Feed Ownership Confusion
The generator creates `feed.xml` in GCS, but the hub's Podcast model and routes could generate the feed directly from the database.

---

## Future Growth Considerations

### With No Active Users Today

The architecture is over-engineered for current scale:
- No traffic to scale
- No concurrent processing needs
- No fault isolation benefits being realized

### What Would Trigger Need for Separation

1. **High-volume TTS processing**: Thousands of episodes per day requiring elastic scaling
2. **Different SLA requirements**: Web must be 99.99% but processing can be 99%
3. **Cost optimization**: Wanting to use spot instances for processing only
4. **Language rewrite**: Rewriting processor in a faster language

**Assessment:** None of these are likely in the near-to-medium term.

### What Consolidation Enables

1. **Faster feature development**: One codebase, one deployment, one mental model
2. **Simpler debugging**: All logs in one place, Rails error tracking
3. **Better testing**: End-to-end tests without mocking service boundaries
4. **Easier onboarding**: One app to understand
5. **Reduced infrastructure**: Eliminate Cloud Run, Cloud Tasks overhead

---

## Options Analysis

### Option 1: Keep Separate (Status Quo)

**What it means:**
- Continue with current architecture
- Maintain two codebases, two deployments
- Invest in better observability to reduce debugging pain

**Pros:**
- No migration work
- Preserves theoretical scaling flexibility
- Generator stays simple

**Cons:**
- Ongoing complexity tax
- Two deployment systems
- Development friction continues

**Effort:** None
**Risk:** Low (no change)
**Recommendation:** ❌ Not recommended given your goals

---

### Option 2: Merge Generator into Hub

**What it means:**
- Move `lib/tts/` and processing logic into Hub
- Use Solid Queue jobs for TTS processing
- Eliminate Cloud Tasks, callback API, and Cloud Run
- Hub handles everything end-to-end

**Pros:**
- Single codebase, single deployment
- Simpler development and debugging
- Eliminates Cloud Tasks costs
- Eliminates cold start latency
- Can still use background jobs for async processing
- RSS feed can be generated from database (no manifest.json needed)

**Cons:**
- Migration effort required
- Lose theoretical independent scaling
- Hub VM needs enough resources for TTS processing (already has 2Gi+ available)

**Effort:** Medium
**Risk:** Medium (gem integration unknowns, multi-tenancy adaptation, thread pooling compatibility)
**Recommendation:** ✅ Recommended

---

### Option 3: Move Hub to Cloud Run

**What it means:**
- Containerize Hub for Cloud Run
- Both services serverless
- Use Cloud SQL instead of SQLite
- Use Cloud Storage for Active Storage

**Pros:**
- Fully serverless architecture
- True auto-scaling for both components
- Pay-per-use pricing

**Cons:**
- Significant migration effort
- Cloud SQL adds cost and complexity
- SQLite simplicity is a feature
- Still have two services to maintain

**Effort:** High
**Risk:** High (database migration, different operational model)
**Recommendation:** ❌ Not recommended (adds complexity, not aligned with goals)

---

### Option 4: Create Shared Gem

**What it means:**
- Extract common code (GCS uploaders, etc.) into a shared gem
- Keep services separate but share code
- Reduce duplication while maintaining separation

**Pros:**
- Less code duplication
- Services stay independent

**Cons:**
- Gem versioning adds complexity
- Still have two services, two deployments
- Doesn't address root complexity issues

**Effort:** Medium
**Risk:** Low
**Recommendation:** ❌ Not recommended (half-measure that doesn't solve core issues)

---

## Recommended Path: Merge Generator into Hub

### Design Decisions

Based on requirements gathering:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **manifest.json** | Eliminate | Generate RSS from Episode records directly |
| **Podcast config** | Hardcode defaults | No per-podcast customization needed |
| **Rollout strategy** | Hardcoded allowlist | No migration - test with Jesse's podcast first |

---

### Migration Strategy

#### Phase 0: Prerequisites ⚠️

Before starting migration, complete these prerequisites:

**0.1 Add TTS gems to Hub Gemfile**
```ruby
# hub/Gemfile - add these
gem "google-cloud-text_to_speech", "~> 2.0"
gem "ruby-mp3info"
```

Verify no conflicts with existing Google gems (`google-cloud-storage`, `google-cloud-tasks`).

**0.2 Verify Generator tests pass**
```bash
# From root directory
bundle exec rake test
```

Current status: ✅ 135 runs, 362 assertions, 0 failures

**0.3 Design podcast config injection**

The generator reads hardcoded `config/podcast.yml`. Need to inject from Podcast model:

```ruby
# Current: EpisodeProcessor reads from YAML
config = YAML.load_file("config/podcast.yml")

# Target: Receive podcast config as parameter
def initialize(podcast_id:, podcast_config:, ...)
  @podcast_config = podcast_config  # Hash with title, description, artwork_url, etc.
end
```

Podcast model already has `title` and `description` columns. Need to add:
- `artwork_url` column (or use default from podcast.yml)
- `author` column (or use default)
- `email` column (or use default)

**0.4 Document manifest.json elimination**

Current state:
- Generator writes to `manifest.json` on episode publish
- Generator reads `manifest.json` to generate `feed.xml`
- Hub has duplicate `EpisodeManifest` class for delete operations

Target state:
- RSS feed generated from `Episode.where(podcast: podcast, status: :complete)`
- `manifest.json` no longer written or read
- Delete operation just regenerates feed from DB

**0.5 Define callback behavior during parallel phase**

During coexistence, both paths may update episodes:
- External generator: HTTP PATCH to `/api/internal/episodes/:id`
- Internal processing: Direct `episode.update!(...)`

Conflict prevention:
- Podcast allowlist checked at dispatch time, not completion time
- Episode tracks `processing_mode` to know which path owns it
- Callback endpoint only accepts updates for externally-processed episodes

**0.6 Identify dead code for cleanup**

Files to delete during migration:
- `lib/firestore_client.rb` - not imported anywhere
- `/publish` endpoint in `api.rb` - unused (replaced by `/process`)
- `lib/cloud_tasks_enqueuer.rb` in generator - only Hub dispatches tasks

---

#### Phase 1: Copy and Adapt TTS Library

**1.1 Copy library files**
```
lib/tts/                    → hub/lib/tts/
lib/tts.rb                  → hub/lib/tts.rb
lib/episode_processor.rb    → hub/app/services/tts/episode_processor.rb
lib/rss_generator.rb        → hub/app/services/tts/rss_generator.rb
lib/filename_generator.rb   → hub/app/services/tts/filename_generator.rb
```

**1.2 Replace puts with Rails.logger**

Files with `puts` statements to fix:
- `lib/episode_processor.rb` (14 occurrences)
- `lib/tts.rb` (3 occurrences)

Pattern:
```ruby
# Before
puts "✓ Generated #{format_size(audio_content.bytesize)}"

# After
Rails.logger.info "✓ Generated #{format_size(audio_content.bytesize)}"
```

**1.3 Adapt Logger patterns**

Generator uses custom `log_or_puts` helper. Replace with:
```ruby
def log(message, level: :info)
  Rails.logger.public_send(level, "[TTS] #{message}")
end
```

**1.4 Review thread pooling**

Generator's `ChunkedSynthesizer` uses `Concurrent::Future` for parallel TTS API calls. Verify compatibility with Solid Queue:
- Solid Queue runs jobs in separate processes (not threads)
- Thread pooling within a job should be fine
- Test with realistic content to verify no deadlocks

**1.5 Adapt for multi-tenancy**

Replace hardcoded podcast config with parameter injection:
```ruby
class Tts::EpisodeProcessor
  def initialize(episode:, podcast_config:)
    @episode = episode
    @podcast_config = podcast_config  # From Podcast model + defaults
  end
end
```

**1.6 Copy and adapt tests**

Copy `test/test_*.rb` to `hub/test/lib/tts/` and adapt:
- Change `require` paths
- Use Rails test helpers
- Mock Rails.logger instead of $stdout

---

#### Phase 2: Create Processing Job

Jobs should be thin wrappers that delegate to services:

```ruby
# app/jobs/generate_audio_job.rb
class GenerateAudioJob < ApplicationJob
  def perform(episode)
    GenerateEpisodeAudio.call(episode)
  end
end

# app/services/generate_episode_audio.rb
class GenerateEpisodeAudio
  def self.call(episode)
    new(episode).call
  end

  def call
    # All business logic lives here:
    # 1. Build podcast config from defaults
    # 2. Call Tts::EpisodeProcessor
    # 3. Upload audio to GCS
    # 4. Update episode record
    # 5. Regenerate RSS feed
  end
end
```

Tasks:
1. Create `GenerateEpisodeAudio` service with all processing logic
2. Create thin `GenerateAudioJob` that calls the service
3. Add `processing_mode` column to episodes (`:internal` or `:external`)

---

#### Phase 3: Update Episode Flow with Feature Flag

No migration needed - hardcode the test podcast:

```ruby
# app/services/submit_episode_for_processing.rb
INTERNAL_TTS_PODCAST_IDS = [
  "podcast_xxx"  # Jesse's podcast for testing
].freeze

def call
  if INTERNAL_TTS_PODCAST_IDS.include?(episode.podcast.podcast_id)
    GenerateAudioJob.perform_later(episode)
  else
    CloudTasksEnqueuer.enqueue_episode_processing(episode)
  end
end
```

Tasks:
1. Add `INTERNAL_TTS_PODCAST_IDS` constant with your podcast_id
2. Route matching episodes to `GenerateAudioJob`
3. Keep callback API endpoint for external-mode episodes
4. Once verified, add all podcast_ids to the list (or remove the check entirely)

---

#### Phase 4: Eliminate manifest.json

1. Create `RssFeedGenerator` service that queries Episode records
2. Generate feed on episode completion (cache to GCS)
3. Remove manifest.json reads/writes from all code
4. Delete Hub's duplicate `EpisodeManifest` class
5. Update `DeleteEpisodeJob` to regenerate feed from DB

---

#### Phase 5: Gradual Rollout

1. Deploy with all podcasts using external processing (flag = false)
2. Enable for test podcast, verify end-to-end
3. Enable for additional podcasts one at a time
4. Once all podcasts migrated, proceed to cleanup

---

#### Phase 6: Cleanup

1. Remove `INTERNAL_TTS_PODCAST_IDS` check (all podcasts use internal)
2. Remove generator-specific files from root:
   - `api.rb`, `Dockerfile`, `config.ru`
   - `lib/` directory (all files)
   - `test/` directory (generator tests)
3. Remove Cloud Tasks configuration from Hub
4. Remove callback API endpoint (`/api/internal/episodes/:id`)
5. Update GitHub Actions to only deploy Hub
6. Delete Cloud Run service
7. Delete Cloud Tasks queue

### How to Make Changes Safely

#### Hardcoded Podcast Allowlist

No migration needed - use a constant:

```ruby
# Rollout sequence:
# 1. Deploy with empty INTERNAL_TTS_PODCAST_IDS (no behavior change)
# 2. Add your podcast_id to the list, deploy
# 3. Verify end-to-end: submit episode, check audio, check feed
# 4. Add remaining podcast_ids (or remove check entirely)
# 5. Proceed to cleanup
```

#### Rollback Plan

- **Instant revert**: Remove podcast_id from `INTERNAL_TTS_PODCAST_IDS`, deploy
- **Generator stays deployed**: Keep Cloud Run service running but dormant
- **No data migration**: Same GCS bucket structure, same Episode records
- **Callback endpoint preserved**: External processing path still works

#### Verification Checklist

Before enabling internal processing for a podcast:
- [ ] TTS gems installed and working
- [ ] All generator tests passing in Hub
- [ ] Test episode generated successfully
- [ ] Audio file exists in GCS at expected path
- [ ] RSS feed includes new episode
- [ ] Episode record updated with gcs_episode_id, duration, size

---

## Confidence Builders

### Testing Strategy

1. **Unit tests for TTS library**: Already exist, copy to hub
2. **Integration tests**: Create test that submits episode and verifies audio generated
3. **Comparison tests**: Generate same content with both systems, compare audio files
4. **Smoke tests post-deploy**: Automated test that creates real episode after each deploy

### Monitoring

1. **Job success rate**: Solid Queue dashboard shows failed jobs
2. **Processing duration**: Track how long TTS takes
3. **Error alerting**: Rails error tracking (Sentry, Honeybadger, etc.)
4. **GCS verification**: Ensure files exist after processing

### Reversibility

- Generator can stay deployed but unused
- Feature flag allows instant revert
- No database schema changes that prevent rollback
- GCS structure unchanged

---

## Cost Comparison

### Current Architecture

| Service | Monthly Cost (estimated) |
|---------|-------------------------|
| Cloud Run (min 0, low usage) | ~$5-20 |
| Cloud Tasks | ~$0 (free tier) |
| GCP VM (Hub) | ~$30-50 |
| GCS Storage | ~$1-5 |
| **Total** | **~$36-75** |

### Merged Architecture

| Service | Monthly Cost (estimated) |
|---------|-------------------------|
| GCP VM (Hub + Processing) | ~$30-50 |
| GCS Storage | ~$1-5 |
| **Total** | **~$31-55** |

**Savings:** $5-20/month in Cloud Run costs, plus simpler billing.

---

## Timeline Estimate

| Phase | Scope |
|-------|-------|
| Phase 1 | Copy TTS library, adapt, test |
| Phase 2 | Create processing job |
| Phase 3 | Update episode flow |
| Phase 4 | RSS generation |
| Phase 5 | Cleanup |

*Note: Actual duration depends on available time and testing depth.*

---

## Decision Checklist

Before proceeding, confirm:

- [ ] Comfortable with single-server architecture for now
- [ ] Hub VM has sufficient resources (RAM, CPU) for TTS processing
- [ ] Acceptable to have TTS processing in same process as web requests
- [ ] Feature flag approach acceptable for safe migration
- [ ] Can tolerate brief period of parallel systems during migration

---

## Conclusion

Given:
- No active daily users
- Goals of reducing complexity and improving velocity
- No need for independent scaling
- Willingness to consolidate deployments

**Merge the generator into the hub.** The split architecture was reasonable for a TTS-focused tool that later grew a web layer, but now that the Hub is the primary interface and the generator is just a processing backend, consolidation will pay dividends in development speed and operational simplicity.

The migration can be done safely with feature flags and parallel processing, allowing verification before committing to the new architecture.
