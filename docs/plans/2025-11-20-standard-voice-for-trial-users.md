# Standard Voice for Trial Users

## Overview

Enable episode submission for all tiers using a tiered voice system:
- Non-unlimited tiers get 1 trial episode with Standard voice
- Unlimited tier keeps unlimited episodes with Chirp3-HD voice

## Context

Currently only `unlimited` tier users can submit episodes, using the premium Chirp3-HD voice ($30/1M chars). We want to let all users try the service with a cheaper Standard voice ($4/1M chars) while limiting abuse risk.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Voice for non-unlimited | `en-GB-Standard-D` | 7.5x cheaper than Chirp3-HD, good quality |
| Episode limit | 1 per non-unlimited user | Prevents abuse, encourages upgrades |
| Character limit | 10K (existing) | ~15 min podcast, enough to try service |
| Track episode usage | Boolean on User | Simple, permanent (one shot only) |
| Store voice on Episode | No | Pass through to TTS worker, don't persist |
| Voice selection logic | Service object | Allows future expansion (user preferences) |

## Tier Summary

| Tier | Episodes | Chars/Episode | Voice |
|------|----------|---------------|-------|
| free | 1 | 10K | Standard |
| basic | 1 | 10K | Standard |
| plus | 1 | 10K | Standard |
| premium | 1 | 10K | Standard |
| unlimited | unlimited | unlimited | Chirp3-HD |

## Cost Analysis

At max usage (10K chars with Standard voice):
- TTS cost per trial episode: $0.04
- Acceptable loss for user acquisition

## Implementation

### 1. Add `trial_episode_used` to users table

Migration to add boolean column, default false.

### 2. Create `VoiceSelector` service

```ruby
class VoiceSelector
  STANDARD_VOICE = "en-GB-Standard-D"
  PREMIUM_VOICE = "en-GB-Chirp3-HD-Enceladus"

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    user.unlimited? ? PREMIUM_VOICE : STANDARD_VOICE
  end

  private

  attr_reader :user
end
```

### 3. Update submission access check

Replace `submissions_enabled?` with trial episode check:
- Unlimited users: always allowed
- Other users: allowed if `trial_episode_used` is false

### 4. Update `EpisodeSubmissionService`

- Call `VoiceSelector` to get voice name
- Pass voice to `CloudTasksEnqueuer`
- Set `trial_episode_used = true` on user after successful submission

### 5. Update `CloudTasksEnqueuer`

Add `voice_name` to task payload sent to TTS worker.

### 6. Update TTS API worker

Read `voice_name` from request body instead of using default from `TTS::Config`.

## Files to Change

- `hub/db/migrate/xxx_add_trial_episode_used_to_users.rb` (new)
- `hub/app/services/voice_selector.rb` (new)
- `hub/app/models/user.rb` - update `submissions_enabled?`
- `hub/app/services/episode_submission_service.rb` - add voice selection
- `hub/app/services/cloud_tasks_enqueuer.rb` - pass voice in payload
- `api.rb` - read voice from request

## Future Considerations

- Character tracking per tier for proper paid tier limits
- User voice preferences (VoiceSelector can expand to handle this)
- Multiple voices per tier as upsell
