# Log Consistency Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Standardize logging across Hub and Generator services with consistent event-based format optimized for debugging.

**Architecture:** Event-based key-value logging (`event=name key=value`) for all custom logs. Hub logs critical request lifecycle events. Generator uses consistent event format for errors. Console output suppressed in production.

**Tech Stack:** Ruby on Rails 8, Sinatra, Ruby Logger

---

## Task 1: Add Hub Episode Creation Logging

**Files:**
- Modify: `hub/app/services/episode_submission_service.rb`

**Step 1: Add logging after episode save**

Edit `hub/app/services/episode_submission_service.rb`, modify `call` method:

```ruby
def call
  episode = build_episode
  return Result.failure(episode) unless episode.save

  Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{podcast.users.first.id} title=\"#{episode.title}\""

  staging_path = upload_to_staging(episode)
  enqueue_processing(episode, staging_path)

  Result.success(episode)
end
```

**Step 2: Verify logging in test**

Run:
```bash
cd hub && rails test test/services/episode_submission_service_test.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add hub/app/services/episode_submission_service.rb
git commit -m "feat(hub): add episode creation logging"
```

---

## Task 2: Add Hub GCS Upload Logging

**Files:**
- Modify: `hub/app/services/episode_submission_service.rb`

**Step 1: Add logging after staging upload**

Edit `hub/app/services/episode_submission_service.rb`, modify `upload_to_staging` method:

```ruby
def upload_to_staging(episode)
  content = uploaded_file.read
  filename = "#{episode.id}-#{Time.now.to_i}.md"

  staging_path = gcs_uploader.upload_staging_file(content: content, filename: filename)

  Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

  staging_path
end
```

**Step 2: Run tests**

Run:
```bash
cd hub && rails test test/services/episode_submission_service_test.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add hub/app/services/episode_submission_service.rb
git commit -m "feat(hub): add staging upload logging"
```

---

## Task 3: Add Hub Task Enqueue Logging

**Files:**
- Modify: `hub/app/services/episode_submission_service.rb`

**Step 1: Add logging after task enqueue**

Edit `hub/app/services/episode_submission_service.rb`, modify `enqueue_processing` method:

```ruby
def enqueue_processing(episode, staging_path)
  task_name = enqueuer.enqueue_episode_processing(
    episode_id: episode.id,
    podcast_id: podcast.podcast_id,
    staging_path: staging_path,
    metadata: {
      title: episode.title,
      author: episode.author,
      description: episode.description
    }
  )

  Rails.logger.info "event=task_enqueued episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} task_name=#{task_name}"
end
```

**Step 2: Update CloudTasksEnqueuer to return task name**

Edit `hub/app/services/cloud_tasks_enqueuer.rb`, ensure `enqueue_episode_processing` returns task name:

```ruby
def enqueue_episode_processing(episode_id:, podcast_id:, staging_path:, metadata:)
  task_payload = {
    episode_id: episode_id,
    podcast_id: podcast_id,
    staging_path: staging_path,
    title: metadata[:title],
    author: metadata[:author],
    description: metadata[:description]
  }

  response = client.create_task(parent: queue_path, task: build_task(task_payload))
  response.name
end
```

**Step 3: Run tests**

Run:
```bash
cd hub && rails test test/services/
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add hub/app/services/episode_submission_service.rb hub/app/services/cloud_tasks_enqueuer.rb
git commit -m "feat(hub): add task enqueue logging"
```

---

## Task 4: Add Hub Authentication Logging

**Files:**
- Modify: `hub/app/services/authenticate_magic_link.rb`

**Step 1: Add logging on successful authentication**

Edit `hub/app/services/authenticate_magic_link.rb`, add after successful validation:

```ruby
def call
  user = find_user_by_token
  return nil unless user

  ValidateAuthToken.call(user: user)

  InvalidateAuthToken.call(user: user)

  Rails.logger.info "event=user_authenticated user_id=#{user.id} email=#{user.email_address}"

  user
end
```

**Step 2: Run tests**

Run:
```bash
cd hub && rails test test/services/authenticate_magic_link_test.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add hub/app/services/authenticate_magic_link.rb
git commit -m "feat(hub): add authentication success logging"
```

---

## Task 5: Standardize Hub InvalidateAuthToken Logging

**Files:**
- Modify: `hub/app/services/invalidate_auth_token.rb`

**Step 1: Update to event format**

Edit `hub/app/services/invalidate_auth_token.rb`:

```ruby
def call
  @user.update!(
    auth_token: nil,
    auth_token_expires_at: nil
  )

  Rails.logger.info "event=auth_token_invalidated user_id=#{@user.id}"

  @user
end
```

**Step 2: Run tests**

Run:
```bash
cd hub && rails test test/services/invalidate_auth_token_test.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add hub/app/services/invalidate_auth_token.rb
git commit -m "refactor(hub): standardize auth token invalidation logging"
```

---

## Task 6: Add Hub User Signup Logging

**Files:**
- Modify: `hub/app/services/create_user.rb`

**Step 1: Add logging after user creation**

Edit `hub/app/services/create_user.rb`, add after user and podcast creation:

```ruby
def call
  user = User.find_or_create_by!(email_address: @email_address)

  podcast = CreateDefaultPodcast.call(user: user) if user.podcasts.empty?

  Rails.logger.info "event=user_created user_id=#{user.id} email=#{user.email_address} podcast_id=#{podcast&.podcast_id}"

  Result.new(user: user, podcast: podcast)
end
```

**Step 2: Run tests**

Run:
```bash
cd hub && rails test test/services/create_user_test.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add hub/app/services/create_user.rb
git commit -m "feat(hub): add user signup logging"
```

---

## Task 7: Standardize Generator Error Logging

**Files:**
- Modify: `api.rb`

**Step 1: Update publish endpoint error handling**

Edit `api.rb`, replace lines 57-60:

```ruby
rescue StandardError => e
  logger.error "event=publish_error error_class=#{e.class} error_message=\"#{e.message}\""
  logger.error "event=publish_error_backtrace backtrace=\"#{e.backtrace.first(5).join(' | ')}\""
  halt 500, json(status: "error", message: "Internal server error")
end
```

**Step 2: Update process endpoint error handling**

Edit `api.rb`, replace lines 74-80:

```ruby
rescue JSON::ParserError => e
  logger.error "event=process_json_error error_message=\"#{e.message}\""
  halt 400, json(status: "error", message: "Invalid JSON payload")
rescue StandardError => e
  logger.error "event=process_error error_class=#{e.class} error_message=\"#{e.message}\""
  logger.error "event=process_error_backtrace backtrace=\"#{e.backtrace.first(5).join(' | ')}\""
  halt 500, json(status: "error", message: "Internal server error")
end
```

**Step 3: Run tests**

Run:
```bash
rake test
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add api.rb
git commit -m "refactor: standardize Generator error logging to event format"
```

---

## Task 8: Add Episode ID to Generator Processing Logs

**Files:**
- Modify: `api.rb`

**Step 1: Add episode_id to all processing logs**

Edit `api.rb`, update `process_episode_task` method to include episode_id:

```ruby
def process_episode_task(payload)
  podcast_id = payload["podcast_id"]
  title = payload["title"]
  author = payload["author"]
  description = payload["description"]
  staging_path = payload["staging_path"]
  episode_id = payload["episode_id"]

  logger.info "event=processing_started podcast_id=#{podcast_id} episode_id=#{episode_id} title=\"#{title}\""

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
  markdown_content = gcs.download_file(remote_path: staging_path)
  logger.info "event=file_downloaded podcast_id=#{podcast_id} episode_id=#{episode_id} size_bytes=#{markdown_content.bytesize}"

  processor = EpisodeProcessor.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"), podcast_id)
  episode_data = processor.process(title: title, author: author, description: description, markdown_content: markdown_content)
  logger.info "event=episode_processed podcast_id=#{podcast_id} episode_id=#{episode_id} gcs_episode_id=#{episode_data['id']}"

  gcs.delete_file(remote_path: staging_path)
  logger.info "event=staging_cleaned podcast_id=#{podcast_id} episode_id=#{episode_id} staging_path=#{staging_path}"

  if episode_id
    logger.info "event=hub_callback_attempting podcast_id=#{podcast_id} episode_id=#{episode_id}"
    notify_hub_complete(episode_id: episode_id, episode_data: episode_data)
  else
    logger.info "event=hub_callback_skipped podcast_id=#{podcast_id} reason=no_episode_id"
  end

  logger.info "event=processing_completed podcast_id=#{podcast_id} episode_id=#{episode_id}"
rescue StandardError => e
  notify_hub_failed(episode_id: episode_id, error_message: e.message) if episode_id
  raise
end
```

**Step 2: Run tests**

Run:
```bash
rake test
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add api.rb
git commit -m "feat: add episode_id to all Generator processing logs"
```

---

## Task 9: Suppress EpisodeProcessor Console Output in Production

**Files:**
- Modify: `lib/episode_processor.rb`

**Step 1: Add environment check for console output**

Edit `lib/episode_processor.rb`, add logger parameter and conditional output:

```ruby
class EpisodeProcessor
  attr_reader :bucket_name, :podcast_id

  def initialize(bucket_name, podcast_id, logger: nil)
    @bucket_name = bucket_name
    @podcast_id = podcast_id
    @logger = logger
  end

  def process(title:, author:, description:, markdown_content:)
    print_start(title)

    text = TextProcessor.convert_to_plain_text(markdown_content)
    log_or_puts "✓ Converted to #{text.length} characters of plain text"

    log_or_puts "\n[2/3] Generating TTS audio..."
    tts = TTS.new
    audio_content = tts.synthesize(text)
    log_or_puts "✓ Generated #{format_size(audio_content.bytesize)} of audio"

    log_or_puts "\n[3/3] Publishing to feed..."
    episode_data = publish_to_feed(audio_content, title, author, description)
    log_or_puts "✓ Published"

    print_success(title)

    episode_data
  end

  private

  def log_or_puts(message)
    if ENV["RACK_ENV"] == "production" || @logger
      @logger&.info(message.gsub(/[✓✗⚠]/, "").strip) if @logger
    else
      puts message
    end
  end

  def print_start(title)
    return if ENV["RACK_ENV"] == "production"

    puts "=" * 60
    puts "Processing: #{title}"
    puts "Podcast ID: #{@podcast_id}"
    puts "=" * 60
  end

  def print_success(title)
    return if ENV["RACK_ENV"] == "production"

    puts "\n#{'=' * 60}"
    puts "✓ Complete: #{title}"
    puts "Podcast ID: #{@podcast_id}"
    puts "=" * 60
  end

  # ... rest of methods unchanged
end
```

**Step 2: Run tests**

Run:
```bash
rake test TEST=test/test_episode_processor.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add lib/episode_processor.rb
git commit -m "refactor: suppress console output in production"
```

---

## Task 10: Add Hub Error Logging

**Files:**
- Modify: `hub/app/services/episode_submission_service.rb`

**Step 1: Add error logging for GCS and Cloud Tasks failures**

Edit `hub/app/services/episode_submission_service.rb`:

```ruby
def call
  episode = build_episode
  return Result.failure(episode) unless episode.save

  Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{podcast.users.first.id} title=\"#{episode.title}\""

  staging_path = upload_to_staging(episode)
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

**Step 2: Run tests**

Run:
```bash
cd hub && rails test test/services/episode_submission_service_test.rb
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add hub/app/services/episode_submission_service.rb
git commit -m "feat(hub): add error logging for episode submission failures"
```

---

## Task 11: Run All Tests and Verify

**Step 1: Run Hub tests**

Run:
```bash
cd hub && rails test
```

Expected: All tests pass

**Step 2: Run Generator tests**

Run:
```bash
rake test
```

Expected: All tests pass

**Step 3: Run RuboCop on Hub**

Run:
```bash
cd hub && bundle exec rubocop
```

Expected: No new offenses

**Step 4: Run RuboCop on Generator**

Run:
```bash
rake rubocop
```

Expected: No new offenses

**Step 5: Commit final verification**

```bash
git add -A
git commit --allow-empty -m "test: verify all log consistency changes pass tests"
```

---

## Completion Checklist

- [ ] Hub logs episode creation with episode_id, podcast_id, user_id
- [ ] Hub logs staging file upload with size
- [ ] Hub logs Cloud Task enqueue with task_name
- [ ] Hub logs authentication success with user_id
- [ ] Hub logs user signup with user_id, podcast_id
- [ ] Hub error logs use event format
- [ ] Generator error logs use event format
- [ ] Generator processing logs include episode_id
- [ ] Console output suppressed in production
- [ ] All tests pass
- [ ] RuboCop passes

---

## Expected Log Flow After Implementation

**Hub (episode creation):**
```
event=episode_created episode_id=123 podcast_id=podcast_xxx user_id=456 title="My Episode"
event=staging_uploaded episode_id=123 staging_path=staging/123-1234567890.md size_bytes=5000
event=task_enqueued episode_id=123 podcast_id=podcast_xxx task_name=projects/xxx/...
```

**Generator (processing):**
```
event=processing_started podcast_id=podcast_xxx episode_id=123 title="My Episode"
event=file_downloaded podcast_id=podcast_xxx episode_id=123 size_bytes=5000
event=episode_processed podcast_id=podcast_xxx episode_id=123 gcs_episode_id=episode_abc
event=staging_cleaned podcast_id=podcast_xxx episode_id=123 staging_path=staging/123-1234567890.md
event=hub_callback_attempting podcast_id=podcast_xxx episode_id=123
event=hub_callback_complete episode_id=123 status=200
event=processing_completed podcast_id=podcast_xxx episode_id=123
```

**Hub (callback):**
```
event=episode_callback_received episode_id=123 status=complete
```
