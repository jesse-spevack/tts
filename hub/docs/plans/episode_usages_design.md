# Episode Usages Design Plan

## Overview

This document describes the design for tracking monthly episode usage to enforce free tier limits.

## Context

The pricing strategy defines two tiers:

| Tier | Price | Episodes/month | Chars/episode |
|------|-------|----------------|---------------|
| FREE | $0 | 2 | 15,000 |
| PRO | $9/mo | Unlimited | 50,000 |

This design addresses the "2 episodes/month" limit for free tier users.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| What counts toward limit | Episode record creation | Simple, predictable for users |
| Failed episodes | Auto-refund | Fair to users, reduces support burden |
| Deleted episodes | Auto-refund | Consistent with failure behavior |
| Track for which tiers | Free tier only | Simpler, no need for PRO analytics yet |
| Additional fields | `episode_count` only | Minimal, can extend later |
| Table name | `episode_usages` | Specific, clear intent |
| Period format | `period_start` date | Clean, easy to query |
| Refund mechanism | Model callbacks | Immediate, no background job needed |
| Abuse prevention | None | Trust users, keep it simple |
| Message tone | Encouraging | Prompt upgrade, not punitive |

## Schema

```ruby
create_table :episode_usages do |t|
  t.references :user, null: false, foreign_key: true
  t.date :period_start, null: false
  t.integer :episode_count, default: 0, null: false
  t.timestamps

  t.index [:user_id, :period_start], unique: true
end
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `user_id` | integer | Foreign key to users table |
| `period_start` | date | First day of the month (e.g., `2025-11-01`) |
| `episode_count` | integer | Number of episodes created this period |

### Constraints

- Unique index on `[user_id, period_start]` prevents duplicate records per user per month
- `episode_count` defaults to 0, cannot be null

## Behavior

### Event-Action Matrix

| Event | Action | Service |
|-------|--------|---------|
| Episode created (free user) | Increment `episode_count` | `RecordEpisodeUsage` |
| Episode status → `failed` | Decrement `episode_count` | `RefundEpisodeUsage` |
| Episode deleted | Decrement `episode_count` | `RefundEpisodeUsage` |
| Episode status → `completed` | No change | — |
| Check if can create | Query usage, compare to limit | `CanCreateEpisode` |

### Lifecycle

```
User clicks "New Episode"
       │
       ▼
┌─────────────────────────┐
│  CanCreateEpisode.call  │
│  - Skip if PRO/unlimited│
│  - Check episode_count  │
│  - Return allowed/denied│
└───────────┬─────────────┘
            │
      ┌─────┴─────┐
      │           │
   allowed     denied
      │           │
      ▼           ▼
  Show form    Show upgrade
      │        message
      ▼
  Episode created
      │
      ▼
┌─────────────────────────┐
│ RecordEpisodeUsage.call │
│ - Find/create usage rec │
│ - Increment count       │
└───────────┬─────────────┘
            │
            ▼
    Episode processing...
            │
      ┌─────┴─────┐
      │           │
  completed    failed
      │           │
      ▼           ▼
   (done)   RefundEpisodeUsage
                  │
                  ▼
            Decrement count
```

## File Structure

```
app/
├── models/
│   └── episode_usage.rb
├── services/
│   ├── can_create_episode.rb
│   ├── record_episode_usage.rb
│   └── refund_episode_usage.rb
db/
└── migrate/
    └── XXXXXX_create_episode_usages.rb
test/
├── models/
│   └── episode_usage_test.rb
└── services/
    ├── can_create_episode_test.rb
    ├── record_episode_usage_test.rb
    └── refund_episode_usage_test.rb
```

## Model

```ruby
# app/models/episode_usage.rb
class EpisodeUsage < ApplicationRecord
  belongs_to :user

  validates :period_start, presence: true
  validates :episode_count, numericality: { greater_than_or_equal_to: 0 }

  def self.current_for(user)
    find_or_initialize_by(
      user: user,
      period_start: Time.current.beginning_of_month.to_date
    )
  end

  def increment!
    with_lock do
      self.episode_count += 1
      save!
    end
  end

  def decrement!
    with_lock do
      self.episode_count = [episode_count - 1, 0].max
      save!
    end
  end
end
```

## Services

### CanCreateEpisode

```ruby
# app/services/can_create_episode.rb
class CanCreateEpisode
  FREE_MONTHLY_LIMIT = 2

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Result.allowed if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = FREE_MONTHLY_LIMIT - usage.episode_count

    if remaining > 0
      Result.allowed(remaining: remaining)
    else
      Result.denied
    end
  end

  private

  attr_reader :user

  def skip_tracking?
    !user.free?
  end

  class Result
    attr_reader :remaining

    def self.allowed(remaining: nil)
      new(allowed: true, remaining: remaining)
    end

    def self.denied
      new(allowed: false, remaining: 0)
    end

    def initialize(allowed:, remaining:)
      @allowed = allowed
      @remaining = remaining
    end

    def allowed?
      @allowed
    end

    def denied?
      !@allowed
    end
  end
end
```

### RecordEpisodeUsage

```ruby
# app/services/record_episode_usage.rb
class RecordEpisodeUsage
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return unless user.free?

    usage = EpisodeUsage.current_for(user)
    usage.increment!
  end

  private

  attr_reader :user
end
```

### RefundEpisodeUsage

```ruby
# app/services/refund_episode_usage.rb
class RefundEpisodeUsage
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return unless user.free?

    usage = EpisodeUsage.current_for(user)
    return unless usage.persisted?

    usage.decrement!
  end

  private

  attr_reader :user
end
```

## Controller Integration

```ruby
# app/controllers/episodes_controller.rb
class EpisodesController < ApplicationController
  before_action :require_can_create_episode, only: [:new, :create]

  def create
    # ... existing episode creation logic ...

    if result.success?
      RecordEpisodeUsage.call(user: Current.user)
      redirect_to episodes_path, notice: "Episode created! Processing..."
    else
      # ... error handling ...
    end
  end

  private

  def require_can_create_episode
    result = CanCreateEpisode.call(user: Current.user)
    return if result.allowed?

    flash[:alert] = "You've used your 2 free episodes this month! " \
                    "Upgrade to PRO for unlimited episodes."
    redirect_to episodes_path
  end
end
```

## Model Callbacks for Refunds

```ruby
# app/models/episode.rb
class Episode < ApplicationRecord
  after_update :refund_usage_on_failure, if: :failed?
  after_destroy :refund_usage_on_delete

  private

  def failed?
    status == "failed" && status_previously_changed?
  end

  def refund_usage_on_failure
    RefundEpisodeUsage.call(user: podcast_owner)
  end

  def refund_usage_on_delete
    RefundEpisodeUsage.call(user: podcast_owner)
  end

  def podcast_owner
    podcast.users.first
  end
end
```

## Migration Plan

### Step 1: Create table and model

1. Generate migration for `episode_usages` table
2. Create `EpisodeUsage` model with validations
3. Write model tests

### Step 2: Create services

1. Implement `CanCreateEpisode` service
2. Implement `RecordEpisodeUsage` service
3. Implement `RefundEpisodeUsage` service
4. Write service tests

### Step 3: Integrate with controllers

1. Replace `require_free_episode_available` with `require_can_create_episode`
2. Call `RecordEpisodeUsage` after episode creation
3. Update flash message to encouraging tone

### Step 4: Add model callbacks

1. Add `after_update` callback for failure refunds
2. Add `after_destroy` callback for deletion refunds
3. Write integration tests

### Step 5: Clean up old implementation

1. Remove `FreeEpisodeClaim` model
2. Remove `free_episode_claims` table
3. Remove `CanClaimFreeEpisode`, `ClaimFreeEpisode`, `ReleaseFreeEpisodeClaim` services
4. Remove related tests

## UI Considerations

### Upgrade Message (shown when limit reached)

> You've used your 2 free episodes this month! Upgrade to PRO for unlimited episodes.

### Remaining Episodes Display (optional, in header or new episode page)

> 1 of 2 free episodes remaining this month

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| User upgrades mid-month | `CanCreateEpisode` returns allowed (skips check for non-free) |
| User downgrades mid-month | Starts counting from current usage |
| Episode count goes negative | Clamped to 0 in `decrement!` |
| Multiple rapid creations | `with_lock` prevents race conditions |
| User has no usage record yet | `find_or_initialize_by` creates one |

## Testing Strategy

### Unit Tests

- `EpisodeUsage` model validations and methods
- Each service in isolation with mocked dependencies

### Integration Tests

- Full flow: create episode → usage incremented
- Full flow: episode fails → usage decremented
- Full flow: episode deleted → usage decremented
- Limit enforcement: 3rd episode blocked for free user
- PRO user bypasses all limits

## Future Considerations

- **Character tracking:** Add `character_count` column if needed for analytics
- **Usage dashboard:** Show users their monthly usage history
- **Soft limits for PRO:** Track PRO usage for potential future limits
- **Rollover:** Allow unused episodes to roll over (not planned)
