# Tier System Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the 5-tier user system (free/basic/plus/premium/unlimited) to 3 tiers (free/pro/unlimited).

**Architecture:** Update the User model enum, adjust character limits in EpisodeSubmissionValidator, simplify voice selection logic, update all tests and fixtures. Migration maps old tiers to new ones.

**Tech Stack:** Rails 8.1, Ruby, Minitest

---

## Task 1: Update User Model Tier Enum

**Files:**
- Modify: `app/models/user.rb:6`
- Modify: `app/models/user.rb:17-22`

**Step 1: Update the tier enum**

Change line 6 from:
```ruby
enum :tier, { free: 0, basic: 1, plus: 2, premium: 3, unlimited: 4 }
```

To:
```ruby
enum :tier, { free: 0, pro: 1, unlimited: 2 }
```

**Step 2: Simplify voice_name method**

Change lines 17-22 from:
```ruby
def voice_name
  if premium? || unlimited?
    "en-GB-Chirp3-HD-Enceladus"
  else
    "en-GB-Standard-D"
  end
end
```

To:
```ruby
def voice_name
  if unlimited?
    "en-GB-Chirp3-HD-Enceladus"
  else
    "en-GB-Standard-D"
  end
end
```

**Step 3: Run tests to see what fails**

Run: `cd hub && bin/rails test test/models/user_test.rb`

Expected: Multiple failures for basic/plus/premium tier tests (these tiers no longer exist).

---

## Task 2: Update User Model Tests

**Files:**
- Modify: `test/models/user_test.rb`

**Step 1: Rewrite tier tests**

Replace lines 46-108 with:

```ruby
test "defaults to free tier" do
  user = User.new(email_address: "test@example.com")
  assert user.free?
end

test "can set tier to pro" do
  user = users(:one)
  user.update!(tier: :pro)
  assert user.pro?
end

test "can set tier to unlimited" do
  user = users(:one)
  user.update!(tier: :unlimited)
  assert user.unlimited?
end

test "email returns email_address" do
  user = users(:one)
  assert_equal user.email_address, user.email
end

test "voice_name returns Standard voice for free tier" do
  user = users(:one)
  user.update!(tier: :free)
  assert_equal "en-GB-Standard-D", user.voice_name
end

test "voice_name returns Standard voice for pro tier" do
  user = users(:one)
  user.update!(tier: :pro)
  assert_equal "en-GB-Standard-D", user.voice_name
end

test "voice_name returns Chirp3-HD voice for unlimited tier" do
  user = users(:one)
  user.update!(tier: :unlimited)
  assert_equal "en-GB-Chirp3-HD-Enceladus", user.voice_name
end
```

**Step 2: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/models/user_test.rb`

Expected: All tests pass.

---

## Task 3: Update User Fixtures

**Files:**
- Modify: `test/fixtures/users.yml`

**Step 1: Simplify fixtures to 3 tiers**

Replace entire file with:

```yaml
one:
  email_address: user1@example.com

two:
  email_address: user2@example.com

free_user:
  email_address: free@example.com
  tier: 0  # free

pro_user:
  email_address: pro@example.com
  tier: 1  # pro

unlimited_user:
  email_address: unlimited@example.com
  tier: 2  # unlimited
```

**Step 2: Run user tests to verify fixtures work**

Run: `cd hub && bin/rails test test/models/user_test.rb`

Expected: All tests pass.

---

## Task 4: Update EpisodeSubmissionValidator

**Files:**
- Modify: `app/services/episode_submission_validator.rb`

**Step 1: Update constants and logic**

Replace entire file with:

```ruby
class EpisodeSubmissionValidator
  MAX_CHARACTERS_FREE = 15_000
  MAX_CHARACTERS_PRO = 50_000

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    ValidationResult.success(
      max_characters: max_characters_for_user
    )
  end

  private

  attr_reader :user

  def max_characters_for_user
    case user.tier
    when "free" then MAX_CHARACTERS_FREE
    when "pro" then MAX_CHARACTERS_PRO
    when "unlimited" then nil
    end
  end

  class ValidationResult
    attr_reader :max_characters

    def self.success(max_characters:)
      new(max_characters: max_characters)
    end

    def initialize(max_characters:)
      @max_characters = max_characters
    end

    def unlimited?
      max_characters.nil?
    end
  end
end
```

**Step 2: Run validator tests to see failures**

Run: `cd hub && bin/rails test test/services/episode_submission_validator_test.rb`

Expected: Failures for basic/plus/premium tests (fixtures no longer exist).

---

## Task 5: Update EpisodeSubmissionValidator Tests

**Files:**
- Modify: `test/services/episode_submission_validator_test.rb`

**Step 1: Rewrite tests for 3 tiers**

Replace entire file with:

```ruby
require "test_helper"

class EpisodeSubmissionValidatorTest < ActiveSupport::TestCase
  test "returns nil max_characters for unlimited tier users" do
    user = users(:unlimited_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_nil result.max_characters
    assert result.unlimited?
  end

  test "returns 15_000 max_characters for free tier users" do
    user = users(:free_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 15_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 50_000 max_characters for pro tier users" do
    user = users(:pro_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 50_000, result.max_characters
    assert_not result.unlimited?
  end
end
```

**Step 2: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/services/episode_submission_validator_test.rb`

Expected: All 3 tests pass.

---

## Task 6: Update CanClaimFreeEpisode Tests

**Files:**
- Modify: `test/services/can_claim_free_episode_test.rb`

**Step 1: Update fixture references**

Replace lines 5-8 (the setup block) with:

```ruby
setup do
  @free_user = users(:free_user)
  @pro_user = users(:pro_user)
  @unlimited_user = users(:unlimited_user)
end
```

**Step 2: Update non-free tier test**

Replace lines 10-13 with:

```ruby
test "returns true for non-free tier user" do
  assert CanClaimFreeEpisode.call(user: @pro_user)
  assert CanClaimFreeEpisode.call(user: @unlimited_user)
end
```

**Step 3: Run tests to verify they pass**

Run: `cd hub && bin/rails test test/services/can_claim_free_episode_test.rb`

Expected: All 4 tests pass.

---

## Task 7: Run Full Test Suite

**Files:** None (verification only)

**Step 1: Run all tests**

Run: `cd hub && bin/rails test`

Expected: All tests pass. If any fail, fix them before proceeding.

**Step 2: Commit the changes**

```bash
cd hub && git add -A && git commit -m "refactor: Simplify tier system to free/pro/unlimited

- Update User.tier enum from 5 tiers to 3
- Adjust character limits: FREE=15K, PRO=50K, UNLIMITED=nil
- Simplify voice_name: only UNLIMITED gets premium voice
- Update all tests and fixtures"
```

---

## Task 8: Create Migration for Existing Data

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_simplify_user_tiers.rb`

**Step 1: Generate migration**

Run: `cd hub && bin/rails generate migration SimplifyUserTiers`

**Step 2: Edit the migration file**

Replace contents with:

```ruby
class SimplifyUserTiers < ActiveRecord::Migration[8.0]
  def up
    # Map old tiers to new tiers:
    # basic(1), plus(2), premium(3) -> pro(1)
    # unlimited(4) -> unlimited(2)
    #
    # Note: free(0) stays as free(0), no change needed

    # First, move unlimited users from 4 to 2
    execute "UPDATE users SET tier = 2 WHERE tier = 4"

    # Then, move basic/plus/premium users to pro (1)
    # basic was 1 (already correct value for pro)
    # plus was 2, premium was 3 -> both become 1
    execute "UPDATE users SET tier = 1 WHERE tier IN (2, 3)"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

**Step 3: Run the migration**

Run: `cd hub && bin/rails db:migrate`

Expected: Migration runs successfully.

**Step 4: Verify in console**

Run: `cd hub && bin/rails runner "puts User.group(:tier).count"`

Expected: Output shows only tiers 0, 1, or 2.

**Step 5: Run tests again**

Run: `cd hub && bin/rails test`

Expected: All tests pass.

**Step 6: Commit the migration**

```bash
cd hub && git add -A && git commit -m "chore: Add migration to simplify user tiers

Maps existing users:
- basic(1), plus(2), premium(3) -> pro(1)
- unlimited(4) -> unlimited(2)
- free(0) unchanged"
```

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Update User model enum and voice_name |
| 2 | Update User model tests |
| 3 | Update User fixtures |
| 4 | Update EpisodeSubmissionValidator |
| 5 | Update EpisodeSubmissionValidator tests |
| 6 | Update CanClaimFreeEpisode tests |
| 7 | Run full test suite and commit |
| 8 | Create and run data migration |

Total: 8 tasks, ~25-30 minutes estimated.
