# Free Episode Claim Feature

## Overview

Free tier users can create 1 free episode. This feature tracks claims and releases them if processing fails.

## Data Model

### Table: `free_episode_claims`

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer | primary key |
| `user_id` | integer | foreign key to users, not null |
| `episode_id` | integer | foreign key to episodes, not null |
| `claimed_at` | datetime | not null, set on creation |
| `released_at` | datetime | nullable, set on failure |
| `created_at` | datetime | Rails timestamp |
| `updated_at` | datetime | Rails timestamp |

**Indexes:**
- `user_id`
- `episode_id`

### Model: `FreeEpisodeClaim`

- `belongs_to :user`
- `belongs_to :episode`
- Scope: `active` — where `released_at` is null

**Active claim definition:** A claim is active if `released_at` is null. A user can only have one active claim.

## Services

### `CanClaimFreeEpisode`

```ruby
CanClaimFreeEpisode.call(user:)
# Returns: true/false
```

Logic:
- Return `true` if user is not free tier
- Return `false` if user is free tier AND has an active claim
- Return `true` if user is free tier AND has no active claim

### `ClaimFreeEpisode`

```ruby
ClaimFreeEpisode.call(user:, episode:)
# Returns: FreeEpisodeClaim record (or nil if not free tier)
```

Logic:
- Return `nil` if user is not free tier
- Create `FreeEpisodeClaim` with `claimed_at: Time.current`

### `ReleaseFreeEpisodeClaim`

```ruby
ReleaseFreeEpisodeClaim.call(episode:)
# Returns: FreeEpisodeClaim record (or nil if none found)
```

Logic:
- Find active claim by `episode_id` (where `released_at` is nil)
- If none found, return nil (already released or not a free tier episode)
- Set `released_at: Time.current`
- Return the claim

This service is idempotent — calling it twice is safe.

## Controller Integration

### `EpisodesController`

```ruby
before_action :require_free_episode_available, only: [:new, :create]

private

def require_free_episode_available
  return unless Current.user.free?
  return if CanClaimFreeEpisode.call(user: Current.user)

  flash[:alert] = "Upgrade to create more episodes."
  redirect_to episodes_path
end
```

In create, after successful submission:

```ruby
if result.success?
  ClaimFreeEpisode.call(user: Current.user, episode: result.episode)
  redirect_to episodes_path, notice: "Episode created! Processing..."
end
```

### `Api::Internal::EpisodesController`

```ruby
def update
  if @episode.update(episode_params)
    ReleaseFreeEpisodeClaim.call(episode: @episode) if @episode.failed?
    render json: { status: "success" }
  else
    # ...
  end
end
```

## Character Limits

Update `EpisodeSubmissionValidator#max_characters_for_user`:

```ruby
def max_characters_for_user
  case
  when user.unlimited? then nil
  when user.premium? || user.plus? then 50_000
  when user.basic? then 25_000
  else 10_000  # free tier
  end
end
```

## Other Changes

- Remove `submissions_enabled?` method from User model
- Remove `require_submission_access` before_action from EpisodesController

## Future Considerations

- **Episode deletion:** If added, should call `ReleaseFreeEpisodeClaim`
- **Episode retry:** If added, retry would need to create a new claim (check eligibility first)
