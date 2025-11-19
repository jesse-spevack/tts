# TTS Cost Safeguards Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent runaway TTS API costs by adding text size limits and retry limits to episode processing.

**Architecture:** Add validation in EpisodeSubmissionService to reject files over 10,000 characters. Add retry_count tracking to Episode model to prevent infinite retry loops. These are defensive measures for a toy app to prevent $300+ monthly bills.

**Tech Stack:** Rails 8, Minitest, Active Record validations

**Context:** Two episodes (15 & 18) with 582KB files retried 13 times each with Chirp3-HD voice ($30/1M chars), costing ~$373 in November. Need immediate safeguards before re-enabling the app.

---

## Task 1: Add Character Limit Validation

**Files:**
- Modify: `app/services/episode_submission_service.rb:14-32`
- Modify: `test/services/episode_submission_service_test.rb:157` (append)

**Step 1: Write the failing test**

Add to `test/services/episode_submission_service_test.rb` after line 157:

```ruby
test "rejects file larger than 10,000 characters" do
  large_content = "a" * 10_001
  large_file = StringIO.new(large_content)

  result = EpisodeSubmissionService.new(
    podcast: @podcast,
    params: @params,
    uploaded_file: large_file,
    gcs_uploader: @mock_uploader,
    enqueuer: @mock_enqueuer
  ).call

  assert result.failure?
  assert_not result.episode.persisted?
  assert_includes result.episode.errors[:content], "is too large (maximum 10,000 characters)"
end

test "accepts file with exactly 10,000 characters" do
  @mock_uploader.define_singleton_method(:upload_staging_file) { |content:, filename:| "staging/#{filename}" }
  @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

  content = "a" * 10_000
  file = StringIO.new(content)

  result = EpisodeSubmissionService.new(
    podcast: @podcast,
    params: @params,
    uploaded_file: file,
    gcs_uploader: @mock_uploader,
    enqueuer: @mock_enqueuer
  ).call

  assert result.success?
  assert result.episode.persisted?
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/episode_submission_service_test.rb:159 -v`

Expected: FAIL - episode should have validation error but doesn't

**Step 3: Add character limit constant and validation**

In `app/services/episode_submission_service.rb`, add after line 1:

```ruby
class EpisodeSubmissionService
  MAX_CHARACTERS = 10_000
```

Then modify the `call` method (lines 14-32) to add validation before save:

```ruby
def call
  episode = build_episode

  # Validate file size before saving
  content = uploaded_file.read
  if content.length > MAX_CHARACTERS
    episode.errors.add(:content, "is too large (maximum #{MAX_CHARACTERS} characters)")
    return Result.failure(episode)
  end

  return Result.failure(episode) unless episode.save

  Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{podcast.users.first.id} title=\"#{episode.title}\""

  staging_path = upload_to_staging(episode, content)
  enqueue_processing(episode, staging_path)

  Result.success(episode)
rescue Google::Cloud::Error => e
  Rails.logger.error "event=gcs_upload_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
  episode&.update(status: "failed", error_message: "Failed to upload to staging: #{e.message}")
  Result.failure(episode)
rescue StandardError => e
  Rails.logger.error "event=episode_submission_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
  episode&.update(status: "failed", error_message: e.message)
  Result.failure(episode)
end
```

**Step 4: Update upload_to_staging to accept content parameter**

Modify `upload_to_staging` method (lines 46-55) to avoid reading file twice:

```ruby
def upload_to_staging(episode, content)
  filename = "#{episode.id}-#{Time.now.to_i}.md"

  staging_path = gcs_uploader.upload_staging_file(content: content, filename: filename)

  Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

  staging_path
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/services/episode_submission_service_test.rb -v`

Expected: All tests PASS (existing tests still work, new tests pass)

**Step 6: Commit**

```bash
git add app/services/episode_submission_service.rb test/services/episode_submission_service_test.rb
git commit -m "feat: add 10,000 character limit to episode submissions

Prevents runaway TTS API costs by rejecting large files upfront.
For context: two 582KB files (515K chars each) cost $373 in retries."
```

---

## Task 2: Add Retry Limit Tracking

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_retry_count_to_episodes.rb`
- Modify: `app/models/episode.rb:1-33`
- Modify: `test/models/episode_test.rb:1` (append)

**Step 1: Write the failing test**

Add to `test/models/episode_test.rb`:

```ruby
test "increments retry_count when marking as failed" do
  episode = episodes(:one)
  assert_equal 0, episode.retry_count

  episode.increment_retry_count!
  assert_equal 1, episode.retry_count

  episode.increment_retry_count!
  assert_equal 2, episode.retry_count
end

test "max_retries_reached? returns true after 3 retries" do
  episode = episodes(:one)

  assert_not episode.max_retries_reached?

  3.times { episode.increment_retry_count! }

  assert episode.max_retries_reached?
end

test "max_retries_reached? returns false before 3 retries" do
  episode = episodes(:one)

  2.times { episode.increment_retry_count! }

  assert_not episode.max_retries_reached?
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/episode_test.rb -v`

Expected: FAIL - NoMethodError: undefined method `retry_count`

**Step 3: Create migration**

Run: `bin/rails generate migration AddRetryCountToEpisodes retry_count:integer`

Edit the generated migration file:

```ruby
class AddRetryCountToEpisodes < ActiveRecord::Migration[8.0]
  def change
    add_column :episodes, :retry_count, :integer, default: 0, null: false
  end
end
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

Expected: Migration runs successfully

**Step 5: Add retry logic to Episode model**

In `app/models/episode.rb`, add after line 10:

```ruby
MAX_RETRIES = 3

def increment_retry_count!
  increment!(:retry_count)
end

def max_retries_reached?
  retry_count >= MAX_RETRIES
end
```

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/episode_test.rb -v`

Expected: All tests PASS

**Step 7: Commit**

```bash
git add db/migrate/*_add_retry_count_to_episodes.rb app/models/episode.rb test/models/episode_test.rb db/schema.rb
git commit -m "feat: add retry_count tracking to episodes

Adds retry_count column and max_retries_reached? method to prevent
infinite retry loops. Episodes will stop retrying after 3 attempts."
```

---

## Task 3: Enforce Retry Limit in Callback Handler

**Files:**
- Modify: `app/controllers/api/internal/episodes_controller.rb:6-15`
- Modify: `test/controllers/api/internal/episodes_controller_test.rb:1` (append)

**Step 1: Write the failing test**

Add to `test/controllers/api/internal/episodes_controller_test.rb`:

```ruby
test "update increments retry count when status changes to failed" do
  episode = episodes(:one)
  assert_equal 0, episode.retry_count

  patch api_internal_episode_url(episode), params: {
    status: "failed",
    error_message: "Test error"
  }, headers: auth_headers

  assert_response :success
  episode.reload
  assert_equal 1, episode.retry_count
end

test "update does not increment retry count when status is not failed" do
  episode = episodes(:one)

  patch api_internal_episode_url(episode), params: {
    status: "complete",
    gcs_episode_id: "test-123"
  }, headers: auth_headers

  assert_response :success
  episode.reload
  assert_equal 0, episode.retry_count
end

test "update logs warning when max retries reached" do
  episode = episodes(:one)
  3.times { episode.increment_retry_count! }

  assert_changes -> { episode.reload.retry_count }, from: 3, to: 4 do
    patch api_internal_episode_url(episode), params: {
      status: "failed",
      error_message: "Test error"
    }, headers: auth_headers
  end

  assert_response :success
  # Note: Would need to check logs for warning message in integration test
end
```

**Step 2: Find auth_headers helper or add it**

Check if `test/controllers/api/internal/episodes_controller_test.rb` has `auth_headers` method. If not, examine existing tests to see how authentication is handled.

**Step 3: Run test to verify it fails**

Run: `bin/rails test test/controllers/api/internal/episodes_controller_test.rb -v`

Expected: FAIL - retry_count not incremented

**Step 4: Add retry tracking to update action**

In `app/controllers/api/internal/episodes_controller.rb`, modify the `update` method (lines 6-15):

```ruby
def update
  if @episode.update(episode_params)
    # Track retries for failed episodes
    if @episode.failed?
      @episode.increment_retry_count!

      if @episode.max_retries_reached?
        Rails.logger.warn "event=max_retries_reached episode_id=#{@episode.id} retry_count=#{@episode.retry_count} error=#{@episode.error_message}"
      end
    end

    Rails.logger.info "event=episode_callback_received episode_id=#{@episode.id} status=#{@episode.status}"
    render json: { status: "success" }
  else
    render json: { status: "error", errors: @episode.errors.full_messages }, status: :unprocessable_entity
  end
rescue ArgumentError => e
  render json: { status: "error", message: e.message }, status: :unprocessable_entity
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/api/internal/episodes_controller_test.rb -v`

Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/controllers/api/internal/episodes_controller.rb test/controllers/api/internal/episodes_controller_test.rb
git commit -m "feat: track retry count on episode failures

Increments retry_count whenever episode status changes to 'failed'.
Logs warning when max retries (3) is reached. This prevents infinite
Cloud Tasks retry loops that caused $373 in TTS costs."
```

---

## Task 4: Display File Size Limit in UI

**Files:**
- Modify: `app/views/episodes/new.html.erb` (find and modify form)
- Modify: `app/helpers/episodes_helper.rb` (add helper method)

**Step 1: Find the episode form view**

Run: `find app/views -name "*episode*" -o -name "*new.html.erb" | grep episode`

**Step 2: Add helper method for character limit**

In `app/helpers/episodes_helper.rb`, add:

```ruby
def max_episode_characters
  EpisodeSubmissionService::MAX_CHARACTERS
end

def format_character_limit(limit)
  "#{number_with_delimiter(limit)} characters"
end
```

**Step 3: Add help text to form**

Locate the file upload field in the episode form and add help text showing the limit. Example for a typical Rails form:

```erb
<%= f.file_field :content, accept: ".md,.txt", required: true %>
<p class="text-sm text-gray-600 mt-1">
  Maximum file size: <%= format_character_limit(max_episode_characters) %>
</p>
```

**Step 4: Test in browser**

Run: `bin/rails server`

Visit: http://localhost:3000/episodes/new

Expected: Form displays "Maximum file size: 10,000 characters" near file upload field

**Step 5: Commit**

```bash
git add app/views/episodes/new.html.erb app/helpers/episodes_helper.rb
git commit -m "feat: display 10K character limit in episode form

Shows users the file size limit upfront to prevent submission errors."
```

---

## Task 5: Add Migration for Existing Episodes

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_set_retry_count_for_existing_episodes.rb`

**Step 1: Create data migration**

Run: `bin/rails generate migration SetRetryCountForExistingEpisodes`

Edit the generated migration:

```ruby
class SetRetryCountForExistingEpisodes < ActiveRecord::Migration[8.0]
  def up
    # Set retry_count to 99 for existing failed episodes to prevent further retries
    # This ensures episodes 15 and 18 won't retry again
    Episode.where(status: "failed").update_all(retry_count: 99)
  end

  def down
    # Reset retry_count for failed episodes
    Episode.where(status: "failed").update_all(retry_count: 0)
  end
end
```

**Step 2: Run migration**

Run: `bin/rails db:migrate`

Expected: Migration runs successfully, existing failed episodes get retry_count = 99

**Step 3: Verify in console**

Run: `bin/rails console`

```ruby
Episode.where(status: "failed").pluck(:id, :retry_count)
# Should show episodes 15 and 18 with retry_count = 99
```

**Step 4: Commit**

```bash
git add db/migrate/*_set_retry_count_for_existing_episodes.rb db/schema.rb
git commit -m "data: set retry_count=99 for existing failed episodes

Prevents episodes 15 and 18 from retrying and incurring more TTS costs.
These episodes already cost ~$373 in November from 13 retries each."
```

---

## Task 6: Update Generator Service Documentation

**Files:**
- Create: `docs/TTS_COST_SAFEGUARDS.md`

**Step 1: Create documentation**

Create `docs/TTS_COST_SAFEGUARDS.md`:

```markdown
# TTS Cost Safeguards

## Overview

This document describes safeguards implemented to prevent runaway TTS API costs.

## Problem

In November 2025, two episodes (15 & 18) with 582KB files (515K chars each) retried 13 times each using Chirp3-HD voice, costing approximately $373:

- Chirp3-HD pricing: $30 per 1M characters after 1M free/month
- 2 episodes × 13 retries × 515K chars = 13.4M characters
- Cost: (13.4M - 1M free) × $30 / 1M = $372

## Implemented Safeguards

### 1. Character Limit (10,000 characters)

**Location:** `app/services/episode_submission_service.rb`

**Behavior:** Rejects file uploads over 10,000 characters before saving to database.

**Cost Impact:** Max $0.30/episode with Chirp3-HD ($0.04 with standard voices)

**Testing:** See `test/services/episode_submission_service_test.rb`

### 2. Retry Limit (3 retries)

**Location:** `app/models/episode.rb`, `app/controllers/api/internal/episodes_controller.rb`

**Behavior:**
- Tracks `retry_count` on Episode model
- Increments on each failure callback
- Logs warning when max retries (3) reached
- Note: Cloud Tasks has its own retry logic; this is for observability

**Cost Impact:** Limits blast radius from infinite retry loops

**Testing:** See `test/models/episode_test.rb`, `test/controllers/api/internal/episodes_controller_test.rb`

### 3. UI Guidance

**Location:** `app/views/episodes/new.html.erb`

**Behavior:** Shows "Maximum file size: 10,000 characters" in form

**Cost Impact:** Prevents user frustration from failed uploads

## Google Cloud Quotas

**Manual configuration required** in GCP Console:

1. Navigate to: https://console.cloud.google.com/apis/api/texttospeech.googleapis.com/quotas

2. Set quotas:
   - **All requests per minute**: 5-20 (was 100)
   - **Chirp3-HD requests per minute**: 1-5 (was 200)
   - **Neural2 requests per minute**: 5-20 (was 1,000)

3. Set budget alerts:
   - Navigate to: https://console.cloud.google.com/billing/budgets
   - Create budget with alerts at 50%, 75%, 90%, 100%

## Voice Cost Comparison

| Voice Type | Cost per 1M chars | Free Tier |
|------------|------------------|-----------|
| Standard | $4 | 4M/month |
| Neural2 | $16 | 1M/month |
| Chirp3-HD | $30 | 1M/month |

**Recommendation for toy app:** Use Neural2 or Standard voices instead of Chirp3-HD

## Monitoring

**Key metrics to watch:**

```ruby
# Episodes by status
Episode.group(:status).count

# Failed episodes with retries
Episode.where(status: "failed").where("retry_count > 0").count

# Episodes approaching max retries
Episode.where(status: "failed").where("retry_count >= 2").pluck(:id, :title, :retry_count, :error_message)
```

**Log events:**

- `event=episode_created` - New episode submitted
- `event=staging_uploaded` - File uploaded, shows `size_bytes`
- `event=max_retries_reached` - Episode hit retry limit
- `event=episode_callback_received` - Status update from Generator

## Recovery

If costs spike again:

1. Check GCP billing dashboard
2. Find offending episodes: `Episode.where(status: "processing").order(created_at: :desc)`
3. Mark as permanently failed: `Episode.find(ID).update!(retry_count: 99, status: :failed)`
4. Check Cloud Tasks queue: `gcloud tasks list --queue=episode-processing --location=us-west3`
5. Purge queue if needed: `gcloud tasks queues purge episode-processing --location=us-west3`

## Future Improvements

- Add admin dashboard showing TTS usage/costs
- Implement voice type selection (let users choose Standard vs Chirp3-HD)
- Add file size validation client-side (JavaScript)
- Add estimated cost preview before submission
```

**Step 2: Commit**

```bash
git add docs/TTS_COST_SAFEGUARDS.md
git commit -m "docs: add TTS cost safeguards documentation

Documents the $373 incident, implemented safeguards, and recovery
procedures for future cost overruns."
```

---

## Verification

After all tasks complete:

**Step 1: Run full test suite**

```bash
bin/rails test
```

Expected: All tests PASS

**Step 2: Check database schema**

```bash
bin/rails db:schema:dump
cat db/schema.rb | grep -A 5 "create_table \"episodes\""
```

Expected: `retry_count` column present with `default: 0, null: false`

**Step 3: Verify in console**

```bash
bin/rails console
```

```ruby
# Check constant
EpisodeSubmissionService::MAX_CHARACTERS
# => 10000

# Check existing failed episodes
Episode.where(id: [15, 18]).pluck(:id, :status, :retry_count)
# => [[15, "failed", 99], [18, "failed", 99]]

# Check Episode methods
Episode.first.respond_to?(:increment_retry_count!)
# => true
Episode.first.respond_to?(:max_retries_reached?)
# => true
```

**Step 4: Deploy to production**

```bash
# Run migrations on production
bin/kamal app exec "bin/rails db:migrate"

# Deploy new code
bin/kamal deploy
```

**Step 5: Test in production**

1. Try submitting a file with 9,000 characters → Should succeed
2. Try submitting a file with 11,000 characters → Should fail with "is too large" error
3. Check that failed episodes 15 and 18 don't retry

---

## Final Checklist

- [ ] All tests passing
- [ ] Character limit enforced (10,000)
- [ ] Retry count tracking active
- [ ] UI shows file size limit
- [ ] Existing failed episodes marked with retry_count=99
- [ ] Documentation complete
- [ ] Google Cloud quotas set (manual step)
- [ ] Budget alerts configured (manual step)
- [ ] Deployed to production
