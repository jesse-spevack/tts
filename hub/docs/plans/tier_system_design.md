# Tier System Design

## Overview

Simplify the current 5-tier system to 3 tiers: FREE, PRO, and UNLIMITED.

## Current State

```ruby
enum :tier, { free: 0, basic: 1, plus: 2, premium: 3, unlimited: 4 }
```

Character limits scattered across `EpisodeSubmissionValidator`:
- FREE: 10,000
- BASIC: 25,000
- PLUS/PREMIUM: 50,000
- UNLIMITED: no limit

## Target State

```ruby
enum :tier, { free: 0, pro: 1, unlimited: 2 }
```

| Tier | Price | Episodes/mo | Chars/episode | Voice |
|------|-------|-------------|---------------|-------|
| FREE | $0 | 2 | 15,000 | Standard |
| PRO | $9/mo | Unlimited | 50,000 | Standard |
| UNLIMITED | — | Unlimited | Unlimited | Premium |

## Schema Changes

Migration to update enum values:

```ruby
class SimplifyUserTiers < ActiveRecord::Migration[8.0]
  def up
    # Map old tiers to new tiers:
    # basic(1), plus(2), premium(3) -> pro(1)
    # unlimited(4) -> unlimited(2)

    User.where(tier: [1, 2, 3]).update_all(tier: 1)  # -> pro
    User.where(tier: 4).update_all(tier: 2)          # -> unlimited
  end

  def down
    # Cannot safely reverse - would lose original tier info
    raise ActiveRecord::IrreversibleMigration
  end
end
```

## Code Changes

### User Model

```ruby
# app/models/user.rb
class User < ApplicationRecord
  enum :tier, { free: 0, pro: 1, unlimited: 2 }

  def voice_name
    if unlimited?
      "en-GB-Chirp3-HD-Enceladus"
    else
      "en-GB-Standard-D"
    end
  end
end
```

### EpisodeSubmissionValidator

```ruby
# app/services/episode_submission_validator.rb
class EpisodeSubmissionValidator
  MAX_CHARACTERS_FREE = 15_000
  MAX_CHARACTERS_PRO = 50_000

  def max_characters_for_user
    case user.tier
    when "free" then MAX_CHARACTERS_FREE
    when "pro" then MAX_CHARACTERS_PRO
    when "unlimited" then nil
    end
  end
end
```

## Files to Update

| File | Change |
|------|--------|
| `app/models/user.rb` | Update tier enum, simplify voice_name |
| `app/services/episode_submission_validator.rb` | Update character limits |
| `db/migrate/XXXX_simplify_user_tiers.rb` | New migration |
| `test/` | Update all tier-related tests and fixtures |

## Testing

- Verify FREE users have 15K limit
- Verify PRO users have 50K limit
- Verify UNLIMITED users have no limit
- Verify voice selection: FREE/PRO get Standard, UNLIMITED gets Premium
- Verify migration correctly maps old tiers

## Dependencies

None. This should be implemented first as other work depends on the simplified tier structure.
