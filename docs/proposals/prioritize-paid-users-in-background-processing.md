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

| User Tier | Priority Value | Constant |
|-----------|---------------|----------|
| Unlimited | `0` | `UNLIMITED_PRIORITY` |
| Complimentary | `0` | `COMPLIMENTARY_PRIORITY` |
| Premium (active subscription) | `0` | `PREMIUM_PRIORITY` |
| Free | `10` | `FREE_PRIORITY` |

Paid tiers all share priority `0` (highest). Free users get priority `10`. The gap between `0` and `10` leaves room for future granularity (e.g., annual vs. monthly subscribers) without a migration.

### Implementation

#### 1. Add a `QueuePriority` concern for episode jobs

Create `app/jobs/concerns/queue_priority.rb`:

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

#### 2. Set priority at enqueue time in each creator service

The `priority` must be set when the job is enqueued, not declared statically on the job class, because it depends on the user. ActiveJob supports this via `set(priority:)`:

```ruby
# In CreatesUrlEpisode#call (and equivalent in each creator service):
ProcessesUrlEpisodeJob
  .set(priority: ProcessesUrlEpisodeJob.priority_for_user(user))
  .perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
```

The same pattern applies to all creator services:
- `CreatesUrlEpisode` → `ProcessesUrlEpisodeJob`
- `CreatesPasteEpisode` → `ProcessesPasteEpisodeJob`
- `CreatesFileEpisode` → `ProcessesFileEpisodeJob`
- `CreatesEmailEpisode` → `ProcessesEmailEpisodeJob`
- `CreatesExtensionEpisode` → `ProcessesFileEpisodeJob`

#### 3. Propagate priority to the audio generation job

`SubmitsEpisodeForProcessing` enqueues `GeneratesEpisodeAudioJob` as a second-stage job. It should inherit the same priority:

```ruby
# In SubmitsEpisodeForProcessing#call:
GeneratesEpisodeAudioJob
  .set(priority: QueuePriority.priority_for_user(episode.user))
  .perform_later(episode_id: episode.id, action_id: Current.action_id)
```

This requires `SubmitsEpisodeForProcessing` to load the user association, which it already does (`episode.user.free?` on line 34).

#### 4. No changes to queue configuration

The `config/queue.yml` stays as-is. A single `default` queue with `workers: queues: "*"` already polls by `(priority, job_id)`. No new queues, no worker reconfiguration, no deployment changes.

### Files Changed

| File | Change |
|------|--------|
| `app/jobs/concerns/queue_priority.rb` | **New.** Defines priority constants and `priority_for_user` class method. |
| `app/jobs/application_job.rb` | Include `QueuePriority` so all jobs have access. |
| `app/services/creates_url_episode.rb` | Set priority on `ProcessesUrlEpisodeJob`. |
| `app/services/creates_paste_episode.rb` | Set priority on `ProcessesPasteEpisodeJob`. |
| `app/services/creates_file_episode.rb` | Set priority on `ProcessesFileEpisodeJob`. |
| `app/services/creates_email_episode.rb` | Set priority on `ProcessesEmailEpisodeJob`. |
| `app/services/creates_extension_episode.rb` | Set priority on `ProcessesFileEpisodeJob`. |
| `app/services/submits_episode_for_processing.rb` | Set priority on `GeneratesEpisodeAudioJob`. |

No database migrations. No new gems. No configuration changes.

### Tests

Add tests to verify:

1. **`QueuePriority` concern**: `priority_for_user` returns `0` for premium/complimentary/unlimited users and `10` for free users.
2. **Each creator service**: Assert that `perform_later` is called with the correct `priority` via `set`. Use `assert_enqueued_with(job:, priority:)` from `ActiveJob::TestHelper`.
3. **`SubmitsEpisodeForProcessing`**: Assert `GeneratesEpisodeAudioJob` is enqueued with the correct priority based on the episode's user tier.

## Alternatives Considered

### Separate Queues (`premium` and `default`)

Configure workers to drain `premium` before `default`:

```yaml
workers:
  - queues: [premium, default]
    threads: 3
```

**Rejected because:**
- Adds deployment configuration complexity — workers must be reconfigured.
- Solid Queue workers with ordered queue lists use strict ordering (drain `premium` completely before touching `default`), which could starve free users entirely during sustained load.
- Priority values within a single queue achieve the same result with proportional fairness — free jobs still run when no premium jobs are waiting.
- Queue-based separation is better suited for isolating fundamentally different workloads (e.g., email delivery vs. audio processing), not for tiering the same workload.

### Priority with Starvation Protection

Add a scheduled job that bumps long-waiting free jobs to a higher priority (e.g., after 5 minutes in queue, set priority to `5`).

**Deferred because:**
- The current scale (3 workers, moderate traffic) makes starvation unlikely.
- Adds operational complexity with a recurring task scanning the queue.
- Worth revisiting if monitoring shows free-tier p95 wait times degrading significantly.

## Rollout

1. Deploy the code change — it applies to newly enqueued jobs only. Jobs already in the queue continue at their current priority (`0`).
2. No feature flag needed. The change is low-risk: if the priority values are wrong, the worst case is the prior behavior (FIFO within same priority).
3. Monitor queue wait times by tier in logs (the `EpisodeJobLogging` concern already logs `user_id` — add `priority` to the structured log payload for observability).

## Future Considerations

- **Starvation monitoring**: Track p95 queue wait time for free-tier jobs. If it exceeds an acceptable threshold, implement the priority escalation mechanism described above.
- **Finer-grained priorities**: The `0`/`10` gap allows inserting tiers (e.g., `5` for annual subscribers) without touching existing logic.
- **Worker scaling**: If queue depth grows, increase `JOB_CONCURRENCY` or `threads` in `config/queue.yml` before adding priority complexity.
