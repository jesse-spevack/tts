# Proposal: Prioritize Paid Users in Background Processing

## Problem

All episode processing jobs currently run at equal priority regardless of user tier. When the queue backs up (3 worker threads, sequential per-user concurrency), a paying premium/unlimited user's episode waits behind free-tier episodes on a first-come-first-served basis. Paid users should experience faster processing as part of the value they're paying for.

## Current Architecture

**Queue system:** Solid Queue (SQLite-backed, in-process with Puma)

**Worker configuration** (`config/queue.yml`):
- Single `default` queue
- 3 worker threads, 1 process (configurable via `JOB_CONCURRENCY`)
- All jobs enqueued with default priority `0`

**Job classes** (all use `queue_as :default`, no explicit priority):

| Job | Concurrency Limit |
|-----|-------------------|
| `ProcessesUrlEpisodeJob` | 1 per user |
| `ProcessesPasteEpisodeJob` | 1 per user |
| `ProcessesFileEpisodeJob` | 1 per user |
| `ProcessesEmailEpisodeJob` | 1 per user |
| `GeneratesEpisodeAudioJob` | 1 per user |
| `DeleteEpisodeJob` | none |

**User tiers** (`User#premium?`, `User#free?`):
- **Free** (`standard` account_type, no active subscription): 2 episodes/month, 15k char limit
- **Premium** (active Stripe subscription): unlimited episodes, 50k char limit
- **Complimentary/Unlimited** (admin-set account_type): unlimited episodes

**Enqueue pattern:** Services call `JobClass.perform_later(episode_id:, user_id:, ...)` with no priority argument.

## Proposed Solution: Solid Queue Priority Values

Use Solid Queue's built-in `priority` column to give paid users' jobs higher priority. In Solid Queue, **lower numeric values execute first**. The ready executions table is indexed on `(priority, job_id)`, so this is the natural, zero-infrastructure way to prioritize.

### Priority Scheme

| User Tier | Priority Value |
|-----------|---------------|
| Unlimited | `0` |
| Complimentary | `0` |
| Premium (active subscription) | `0` |
| Free | `10` |

Paid tiers all share priority `0` (highest). Free users get priority `10`. The gap between `0` and `10` leaves room for future granularity (e.g., annual vs. monthly subscribers) without a migration.

## Implementation Plan

### Step 1: Create `QueuePriority` concern

**New file:** `app/jobs/concerns/queue_priority.rb`

Follows the existing concern pattern (`EpisodeJobLogging`): a module using `ActiveSupport::Concern` with class methods.

```ruby
# frozen_string_literal: true

module QueuePriority
  extend ActiveSupport::Concern

  PREMIUM_PRIORITY = 0
  FREE_PRIORITY = 10

  class_methods do
    def priority_for_user(user)
      user.premium? ? PREMIUM_PRIORITY : FREE_PRIORITY
    end
  end
end
```

This reuses the existing `User#premium?` method which already covers all paid tiers (active subscription, complimentary, unlimited).

### Step 2: Include `QueuePriority` in `ApplicationJob`

**Edit:** `app/jobs/application_job.rb`

```ruby
class ApplicationJob < ActiveJob::Base
  include QueuePriority
end
```

This makes `priority_for_user` available on all job classes, matching the pattern of including `EpisodeJobLogging` directly in each job that needs it.

### Step 3: Set priority in `CreatesUrlEpisode`

**Edit:** `app/services/creates_url_episode.rb` (line 31)

Change:
```ruby
ProcessesUrlEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

To:
```ruby
ProcessesUrlEpisodeJob
  .set(priority: ProcessesUrlEpisodeJob.priority_for_user(user))
  .perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

The `user` local variable is already available via the `attr_reader` on line 40.

### Step 4: Set priority in `CreatesPasteEpisode`

**Edit:** `app/services/creates_paste_episode.rb` (line 31)

Same pattern. The `user` local is available via `attr_reader` on line 42.

Change:
```ruby
ProcessesPasteEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

To:
```ruby
ProcessesPasteEpisodeJob
  .set(priority: ProcessesPasteEpisodeJob.priority_for_user(user))
  .perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

### Step 5: Set priority in `CreatesFileEpisode`

**Edit:** `app/services/creates_file_episode.rb` (line 35)

Same pattern. The `user` local is available via `attr_reader`.

Change:
```ruby
ProcessesFileEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

To:
```ruby
ProcessesFileEpisodeJob
  .set(priority: ProcessesFileEpisodeJob.priority_for_user(user))
  .perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

### Step 6: Set priority in `CreatesEmailEpisode`

**Edit:** `app/services/creates_email_episode.rb` (line 30)

Same pattern. The `user` local is available via `attr_reader`.

Change:
```ruby
ProcessesEmailEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

To:
```ruby
ProcessesEmailEpisodeJob
  .set(priority: ProcessesEmailEpisodeJob.priority_for_user(user))
  .perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

### Step 7: Set priority in `CreatesExtensionEpisode`

**Edit:** `app/services/creates_extension_episode.rb` (lines 45-49)

Same pattern. The `user` local is available via `attr_reader`.

Change:
```ruby
ProcessesFileEpisodeJob.perform_later(
  episode_id: episode.id,
  user_id: episode.user_id,
  action_id: Current.action_id
)
```

To:
```ruby
ProcessesFileEpisodeJob
  .set(priority: ProcessesFileEpisodeJob.priority_for_user(user))
  .perform_later(
    episode_id: episode.id,
    user_id: episode.user_id,
    action_id: Current.action_id
  )
```

### Step 8: Propagate priority in `SubmitsEpisodeForProcessing`

**Edit:** `app/services/submits_episode_for_processing.rb` (line 21)

This service enqueues `GeneratesEpisodeAudioJob` as the second-stage job after content processing. It already accesses `episode.user` (line 34: `episode.user.free?`), so no new association loading is needed.

Change:
```ruby
GeneratesEpisodeAudioJob.perform_later(episode_id: episode.id, action_id: Current.action_id)
```

To:
```ruby
GeneratesEpisodeAudioJob
  .set(priority: GeneratesEpisodeAudioJob.priority_for_user(episode.user))
  .perform_later(episode_id: episode.id, action_id: Current.action_id)
```

### Step 9: Add "Priority processing" to premium feature lists

There are **4 locations** where premium features are listed. Add "Priority processing" to each.

#### 9a. Landing page — monthly pricing panel

**Edit:** `app/views/pages/home.html.erb` (~line 163)

```ruby
features: [
  "Everything in Free, plus:",
  "Unlimited episodes",
  "Up to 50,000 characters",
  "Priority processing",
],
```

#### 9b. Landing page — annual pricing panel

**Edit:** `app/views/pages/home.html.erb` (~line 193)

Same change — add `"Priority processing"` to the features array.

#### 9c. Premium card (billing/upgrade pages)

**Edit:** `app/views/shared/_premium_card.html.erb` (lines 46-50)

```ruby
<% premium_features = [
  "Everything in Free, plus:",
  "Unlimited episodes",
  "Up to 50,000 characters",
  "Priority processing"
] %>
```

#### 9d. Signup modal premium card (if separate)

Check if the signup modal renders `_premium_card.html.erb` or has its own feature list. If it reuses the partial, 9c covers it.

### Step 10: Add `QueuePriority` concern tests

**New file:** `test/jobs/concerns/queue_priority_test.rb`

Follows the exact pattern of `test/jobs/concerns/episode_job_logging_test.rb` — create a test job class that includes the concern, then test the class method.

```ruby
# frozen_string_literal: true

class QueuePriorityTest < ActiveSupport::TestCase
  test "priority_for_user returns PREMIUM_PRIORITY for premium user with active subscription" do
    user = users(:subscriber)
    assert_equal QueuePriority::PREMIUM_PRIORITY, ApplicationJob.priority_for_user(user)
  end

  test "priority_for_user returns PREMIUM_PRIORITY for complimentary user" do
    user = users(:complimentary_user)
    assert_equal QueuePriority::PREMIUM_PRIORITY, ApplicationJob.priority_for_user(user)
  end

  test "priority_for_user returns PREMIUM_PRIORITY for unlimited user" do
    user = users(:unlimited_user)
    assert_equal QueuePriority::PREMIUM_PRIORITY, ApplicationJob.priority_for_user(user)
  end

  test "priority_for_user returns FREE_PRIORITY for free user" do
    user = users(:free_user)
    assert_equal QueuePriority::FREE_PRIORITY, ApplicationJob.priority_for_user(user)
  end

  test "priority_for_user returns FREE_PRIORITY for canceled subscriber" do
    user = users(:canceled_subscriber)
    assert_equal QueuePriority::FREE_PRIORITY, ApplicationJob.priority_for_user(user)
  end

  test "priority_for_user returns FREE_PRIORITY for past due subscriber" do
    user = users(:past_due_subscriber)
    assert_equal QueuePriority::FREE_PRIORITY, ApplicationJob.priority_for_user(user)
  end
end
```

Uses existing fixtures: `subscriber`, `complimentary_user`, `unlimited_user`, `free_user`, `canceled_subscriber`, `past_due_subscriber`.

### Step 11: Update creator service tests to assert priority

Add a test to each creator service test file verifying the correct priority is set. Uses `assert_enqueued_with(job:, priority:)` from `ActiveJob::TestHelper`.

#### 11a. `test/services/creates_url_episode_test.rb`

```ruby
test "enqueues job with premium priority for premium user" do
  premium_user = users(:subscriber)
  assert_enqueued_with(job: ProcessesUrlEpisodeJob, priority: QueuePriority::PREMIUM_PRIORITY) do
    CreatesUrlEpisode.call(podcast: @podcast, user: premium_user, url: "https://example.com/article")
  end
end

test "enqueues job with free priority for free user" do
  free_user = users(:free_user)
  assert_enqueued_with(job: ProcessesUrlEpisodeJob, priority: QueuePriority::FREE_PRIORITY) do
    CreatesUrlEpisode.call(podcast: @podcast, user: free_user, url: "https://example.com/article")
  end
end
```

#### 11b. `test/services/creates_paste_episode_test.rb`

Same pattern with `ProcessesPasteEpisodeJob` and valid paste text.

#### 11c. `test/services/creates_file_episode_test.rb`

Same pattern with `ProcessesFileEpisodeJob` and valid file content.

#### 11d. `test/services/creates_email_episode_test.rb`

Same pattern with `ProcessesEmailEpisodeJob` and valid email body.

#### 11e. `test/services/creates_extension_episode_test.rb`

Same pattern with `ProcessesFileEpisodeJob` and valid extension params.

### Step 12: Update `SubmitsEpisodeForProcessing` test

**Edit:** `test/services/submits_episode_for_processing_test.rb`

Add tests verifying `GeneratesEpisodeAudioJob` is enqueued with the correct priority:

```ruby
test "enqueues audio job with free priority for free user" do
  @episode.user.update!(account_type: :standard)
  assert_enqueued_with(
    job: GeneratesEpisodeAudioJob,
    priority: QueuePriority::FREE_PRIORITY,
    args: [{ episode_id: @episode.id, action_id: nil }]
  ) do
    SubmitsEpisodeForProcessing.call(episode: @episode, content: "Article body.")
  end
end

test "enqueues audio job with premium priority for premium user" do
  @episode.user.update!(account_type: :complimentary)
  assert_enqueued_with(
    job: GeneratesEpisodeAudioJob,
    priority: QueuePriority::PREMIUM_PRIORITY,
    args: [{ episode_id: @episode.id, action_id: nil }]
  ) do
    SubmitsEpisodeForProcessing.call(episode: @episode, content: "Article body.")
  end
end
```

### Step 13: Add priority to structured job logs

**Edit:** `app/jobs/concerns/episode_job_logging.rb`

Add `priority` to the `log_event` "started" call so we can monitor queue priority distribution in production logs:

Change the `with_episode_logging` method to include priority:

```ruby
def with_episode_logging(episode_id:, user_id:, action_id: nil)
  Current.action_id = action_id
  log_event("started", episode_id: episode_id, user_id: user_id, priority: priority)
  yield
  log_event("completed", episode_id: episode_id)
rescue StandardError => e
  log_event("failed", episode_id: episode_id, error: e.class, message: e.message)
  raise
end
```

`priority` is available on all ActiveJob instances via `ActiveJob::Base#priority`.

## Files Changed Summary

| File | Type | Change |
|------|------|--------|
| `app/jobs/concerns/queue_priority.rb` | **New** | `QueuePriority` concern with constants and `priority_for_user` |
| `app/jobs/application_job.rb` | Edit | `include QueuePriority` |
| `app/services/creates_url_episode.rb` | Edit | `.set(priority:)` on `perform_later` |
| `app/services/creates_paste_episode.rb` | Edit | `.set(priority:)` on `perform_later` |
| `app/services/creates_file_episode.rb` | Edit | `.set(priority:)` on `perform_later` |
| `app/services/creates_email_episode.rb` | Edit | `.set(priority:)` on `perform_later` |
| `app/services/creates_extension_episode.rb` | Edit | `.set(priority:)` on `perform_later` |
| `app/services/submits_episode_for_processing.rb` | Edit | `.set(priority:)` on `perform_later` |
| `app/jobs/concerns/episode_job_logging.rb` | Edit | Log `priority` in "started" event |
| `app/views/pages/home.html.erb` | Edit | Add "Priority processing" to 2 premium feature lists |
| `app/views/shared/_premium_card.html.erb` | Edit | Add "Priority processing" to features array |
| `test/jobs/concerns/queue_priority_test.rb` | **New** | Tests for all user tiers |
| `test/services/creates_url_episode_test.rb` | Edit | Assert priority on enqueued job |
| `test/services/creates_paste_episode_test.rb` | Edit | Assert priority on enqueued job |
| `test/services/creates_file_episode_test.rb` | Edit | Assert priority on enqueued job |
| `test/services/creates_email_episode_test.rb` | Edit | Assert priority on enqueued job |
| `test/services/creates_extension_episode_test.rb` | Edit | Assert priority on enqueued job |
| `test/services/submits_episode_for_processing_test.rb` | Edit | Assert priority on enqueued job |

**Total: 2 new files, 16 edited files. No migrations. No new gems. No config changes.**

## What Does NOT Change

- `config/queue.yml` — Single `default` queue, already polls by `(priority, job_id)`
- `db/queue_schema.rb` — `priority` column already exists on `solid_queue_jobs`, `solid_queue_ready_executions`, `solid_queue_blocked_executions`, and `solid_queue_scheduled_executions`
- Job class files — No changes to `queue_as`, `limits_concurrency`, or `perform` signatures
- `DeleteEpisodeJob` — No user context at enqueue time; stays at default priority
- Episode model / status logic — Processing states unchanged
- ActionCable / Turbo Stream broadcasting — Unchanged

## Alternatives Considered

### Separate Queues (`premium` and `default`)

Configure workers to drain `premium` before `default`:

```yaml
workers:
  - queues: [premium, default]
    threads: 3
```

**Rejected because:**
- Solid Queue workers with ordered queue lists use strict ordering (drain `premium` completely before touching `default`), which could starve free users entirely during sustained load.
- Priority values within a single queue achieve the same result with proportional fairness — free jobs still run when no premium jobs are waiting.
- Queue-based separation is better suited for isolating fundamentally different workloads, not tiering the same workload.

### Priority with Starvation Protection

Add a scheduled job that bumps long-waiting free jobs to a higher priority (e.g., after 5 minutes in queue, set priority to `5`).

**Deferred because:**
- The current scale (3 workers, moderate traffic) makes starvation unlikely.
- Adds operational complexity with a recurring task scanning the queue.
- Worth revisiting if monitoring shows free-tier p95 wait times degrading significantly.

## Rollout

1. Deploy the code change — it applies to newly enqueued jobs only. Jobs already in the queue continue at their current priority (`0`).
2. No feature flag needed. The change is low-risk: if the priority values are wrong, the worst case is the prior behavior (FIFO within same priority).
3. Monitor `priority` in structured logs to verify correct distribution across tiers.
