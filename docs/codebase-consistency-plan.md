# Codebase Consistency Improvements Plan

**Created**: 2026-01-03
**Status**: Ready for implementation

## Overview

Three stacked PRs addressing 7 findings from the architecture review:

| PR | Branch | Focus | Findings | Files Changed |
|----|--------|-------|----------|---------------|
| PR1 | `refactor/quick-wins` | Quick wins | #2, #5, #8, #9 | ~12 files |
| PR2 | `refactor/structured-logging` | Structured logging | #6, #7 | ~30 files |
| PR3 | `refactor/service-naming` | Service naming | #1 | ~60 files |

## Decisions Made

- **Service naming convention**: Third-person verbs (e.g., `ValidatesUrl`, `CreatesUrlEpisode`)
- **Duration formatting**: New `FormatsDuration` service
- **Logging approach**: Hybrid StructuredLogging with `default_log_context` override
- **Action ID**: Request-scoped, flows from controller through jobs

---

# PR1: Quick Wins

**Branch**: `refactor/quick-wins`
**Base**: `main`

## Tasks

### Task 1: Extract magic number for URL expiry (#9)

**Files to modify**:
- `lib/app_config.rb`
- `app/services/generate_episode_download_url.rb`

**Changes**:

In `lib/app_config.rb`, add to the `Storage` module:
```ruby
SIGNED_URL_EXPIRY_SECONDS = 300  # 5 minutes
```

In `app/services/generate_episode_download_url.rb:33`, change:
```ruby
# Before
expires: 300,

# After
expires: AppConfig::Storage::SIGNED_URL_EXPIRY_SECONDS,
```

**Commit message**:
```
refactor: extract signed URL expiry to AppConfig constant

Moves magic number 300 (seconds) to AppConfig::Storage::SIGNED_URL_EXPIRY_SECONDS
for better maintainability and documentation.
```

---

### Task 2: Create FormatsDuration service (#2)

**Files to create**:
- `app/services/formats_duration.rb`
- `test/services/formats_duration_test.rb`

**Files to modify**:
- `app/helpers/episodes_helper.rb`
- `app/services/generate_rss_feed.rb`

**New file** `app/services/formats_duration.rb`:
```ruby
# frozen_string_literal: true

class FormatsDuration
  def self.call(duration_seconds)
    new(duration_seconds).call
  end

  def initialize(duration_seconds)
    @duration_seconds = duration_seconds
  end

  def call
    return nil unless @duration_seconds

    minutes = @duration_seconds / 60
    seconds = @duration_seconds % 60
    format("%d:%02d", minutes, seconds)
  end
end
```

**New file** `test/services/formats_duration_test.rb`:
```ruby
# frozen_string_literal: true

require "test_helper"

class FormatsDurationTest < ActiveSupport::TestCase
  test "formats seconds into MM:SS" do
    assert_equal "1:30", FormatsDuration.call(90)
  end

  test "pads seconds with zero" do
    assert_equal "2:05", FormatsDuration.call(125)
  end

  test "handles zero" do
    assert_equal "0:00", FormatsDuration.call(0)
  end

  test "returns nil for nil input" do
    assert_nil FormatsDuration.call(nil)
  end

  test "handles large durations" do
    assert_equal "120:00", FormatsDuration.call(7200)
  end
end
```

**Update** `app/helpers/episodes_helper.rb:29-35`:
```ruby
# Before
def format_duration(duration_seconds)
  return nil unless duration_seconds

  minutes = duration_seconds / 60
  seconds = duration_seconds % 60
  format("%d:%02d", minutes, seconds)
end

# After
def format_duration(duration_seconds)
  FormatsDuration.call(duration_seconds)
end
```

**Update** `app/services/generate_rss_feed.rb:106-112`:
```ruby
# Before
def add_duration(xml, duration_seconds)
  return unless duration_seconds

  minutes = duration_seconds / 60
  seconds = duration_seconds % 60
  xml.tag! "itunes:duration", format("%<min>d:%<sec>02d", min: minutes, sec: seconds)
end

# After
def add_duration(xml, duration_seconds)
  formatted = FormatsDuration.call(duration_seconds)
  xml.tag!("itunes:duration", formatted) if formatted
end
```

**Commit message**:
```
refactor: extract duration formatting to FormatsDuration service

Consolidates duplicate MM:SS formatting logic from EpisodesHelper and
GenerateRssFeed into a single service following the third-person verb
naming convention.
```

---

### Task 3: Standardize ValidatesUrl API (#5)

**Files to modify**:
- `app/services/validates_url.rb`
- `app/services/create_url_episode.rb`
- `app/services/fetches_url.rb`
- `test/services/validates_url_test.rb`

**Update** `app/services/validates_url.rb`:
```ruby
# frozen_string_literal: true

class ValidatesUrl
  def self.call(url)
    new(url).call
  end

  def initialize(url)
    @url = url
  end

  def call
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  private

  attr_reader :url
end
```

**Update call sites** - search for `ValidatesUrl.valid?` and replace with `ValidatesUrl.call`:
- `app/services/create_url_episode.rb`
- `app/services/fetches_url.rb`

**Update** `test/services/validates_url_test.rb` - change all `ValidatesUrl.valid?` to `ValidatesUrl.call`

**Commit message**:
```
refactor: standardize ValidatesUrl to use .call instead of .valid?

Aligns ValidatesUrl with the standard service object API used by all
other services in the codebase.
```

---

### Task 4: SynthesizesAudio keyword arguments (#8)

**Files to modify**:
- `app/services/synthesizes_audio.rb`
- `app/services/generate_episode_audio.rb`
- `test/services/synthesizes_audio_test.rb` (if it has direct calls)

**Update** `app/services/synthesizes_audio.rb:16`:
```ruby
# Before
def call(text, voice: nil)

# After
def call(text:, voice: nil)
```

**Update** `app/services/generate_episode_audio.rb:60`:
```ruby
# Before
synthesizer.call(content_text, voice: voice_name)

# After
synthesizer.call(text: content_text, voice: voice_name)
```

**Commit message**:
```
refactor: use keyword arguments in SynthesizesAudio#call

Changes call(text, voice: nil) to call(text:, voice: nil) for
consistency with other services that use keyword arguments throughout.
```

---

## PR1 Verification

```bash
rake test
bundle exec rubocop
```

**Manual smoke test**:
- Create episode from URL
- Verify duration displays correctly
- Verify audio generates

---

## Create PR1

**After all commits, create PR**:

```bash
git checkout -b refactor/quick-wins
# ... make commits ...
git push -u origin refactor/quick-wins
gh pr create --title "Refactor: Quick wins for codebase consistency" --body "$(cat <<'EOF'
## Summary

Addresses quick-win items from codebase architecture review:

- **#9**: Extract magic number for signed URL expiry to `AppConfig::Storage::SIGNED_URL_EXPIRY_SECONDS`
- **#2**: Create `FormatsDuration` service to consolidate duplicate duration formatting
- **#5**: Standardize `ValidatesUrl` to use `.call` instead of `.valid?`
- **#8**: Use keyword arguments in `SynthesizesAudio#call`

## Test plan

- [ ] All existing tests pass
- [ ] New `FormatsDurationTest` passes
- [ ] Create episode from URL - verify audio generates
- [ ] Verify episode duration displays correctly in UI
EOF
)"
```

---

# PR2: Structured Logging with Action ID

**Branch**: `refactor/structured-logging`
**Base**: `main` (after PR1 merged)

## Tasks

### Task 1: Create StructuredLogging concern

**Files to create**:
- `app/services/concerns/structured_logging.rb`

**New file** `app/services/concerns/structured_logging.rb`:
```ruby
# frozen_string_literal: true

module StructuredLogging
  extend ActiveSupport::Concern

  private

  def log_info(event, **attrs)
    Rails.logger.info build_log_message(event, attrs)
  end

  def log_warn(event, **attrs)
    Rails.logger.warn build_log_message(event, attrs)
  end

  def log_error(event, **attrs)
    Rails.logger.error build_log_message(event, attrs)
  end

  def default_log_context
    { action_id: Current.action_id }.compact
  end

  def build_log_message(event, attrs)
    context = default_log_context.merge(attrs)
    parts = ["event=#{event}"]
    context.each { |k, v| parts << "#{k}=#{v}" if v.present? }
    parts.join(" ")
  end
end
```

**Commit message**:
```
feat: add StructuredLogging concern for consistent log formatting

Provides log_info, log_warn, log_error methods that output structured
event=X key=value format. Includes action_id from Current for request
tracing across services and jobs.
```

---

### Task 2: Refactor EpisodeLogging to use StructuredLogging

**Files to modify**:
- `app/services/concerns/episode_logging.rb`

**Update** `app/services/concerns/episode_logging.rb`:
```ruby
# frozen_string_literal: true

module EpisodeLogging
  extend ActiveSupport::Concern
  include StructuredLogging

  private

  def default_log_context
    super.merge(episode_id: episode&.id).compact
  end

  def episode
    raise NotImplementedError, "#{self.class} must define #episode to use EpisodeLogging"
  end
end
```

**Commit message**:
```
refactor: EpisodeLogging now extends StructuredLogging

EpisodeLogging becomes a thin layer that adds episode_id to the
default log context. All logging methods are inherited from
StructuredLogging.
```

---

### Task 3: Add action_id to Current and ApplicationController

**Files to modify**:
- `app/models/current.rb`
- `app/controllers/application_controller.rb`

**Update** `app/models/current.rb`:
```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :action_id
  delegate :user, to: :session, allow_nil: true

  def self.user_admin?
    user&.admin?
  end
end
```

**Update** `app/controllers/application_controller.rb`:
```ruby
class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  before_action :set_action_id

  allow_browser versions: :modern
  stale_when_importmap_changes

  private

  def set_action_id
    Current.action_id = request.request_id
  end
end
```

**Commit message**:
```
feat: add action_id to Current for request tracing

Sets Current.action_id from Rails request_id on every request,
enabling end-to-end tracing through services and jobs.
```

---

### Task 4: Update jobs to propagate action_id

**Files to modify**:
- `app/jobs/process_url_episode_job.rb`
- `app/jobs/process_paste_episode_job.rb`
- `app/jobs/process_file_episode_job.rb`
- `app/jobs/delete_episode_job.rb`
- `app/jobs/concerns/episode_job_logging.rb`
- `app/services/create_url_episode.rb`
- `app/services/create_paste_episode.rb`
- `app/services/create_file_episode.rb`
- `app/controllers/episodes_controller.rb` (for DeleteEpisodeJob)

**Update** `app/jobs/concerns/episode_job_logging.rb`:
```ruby
# frozen_string_literal: true

module EpisodeJobLogging
  extend ActiveSupport::Concern

  private

  def with_episode_logging(episode_id:, user_id:, action_id: nil)
    Current.action_id = action_id || SecureRandom.uuid
    log_event("started", episode_id: episode_id, user_id: user_id)
    yield
    log_event("completed", episode_id: episode_id)
  rescue StandardError => e
    log_event("failed", episode_id: episode_id, error: e.class, message: e.message)
    raise
  end

  def log_event(status, **attrs)
    event_name = "#{job_type}_#{status}"
    attrs_with_action = { action_id: Current.action_id }.merge(attrs)
    log_parts = attrs_with_action.compact.map { |k, v| "#{k}=#{v}" }.join(" ")
    log_method = status == "failed" ? :error : :info
    Rails.logger.public_send(log_method, "event=#{event_name} #{log_parts}")
  end

  def job_type
    self.class.name.underscore
  end
end
```

**Update each process job** (same pattern for all three):

`app/jobs/process_url_episode_job.rb`:
```ruby
# frozen_string_literal: true

class ProcessUrlEpisodeJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, user_id:, **) { user_id }

  def perform(episode_id:, user_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: user_id, action_id: action_id) do
      episode = Episode.find(episode_id)
      ProcessUrlEpisode.call(episode: episode)
    end
  end
end
```

`app/jobs/process_paste_episode_job.rb`:
```ruby
# frozen_string_literal: true

class ProcessPasteEpisodeJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, user_id:, **) { user_id }

  def perform(episode_id:, user_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: user_id, action_id: action_id) do
      episode = Episode.find(episode_id)
      ProcessPasteEpisode.call(episode: episode)
    end
  end
end
```

`app/jobs/process_file_episode_job.rb`:
```ruby
# frozen_string_literal: true

class ProcessFileEpisodeJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, user_id:, **) { user_id }

  def perform(episode_id:, user_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: user_id, action_id: action_id) do
      episode = Episode.find(episode_id)
      ProcessFileEpisode.call(episode: episode)
    end
  end
end
```

`app/jobs/delete_episode_job.rb`:
```ruby
# frozen_string_literal: true

class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode:, action_id: nil)
    Current.action_id = action_id || SecureRandom.uuid
    DeleteEpisode.call(episode: episode)
  end
end
```

**Update job enqueue sites** to pass `action_id: Current.action_id`:

In `app/services/create_url_episode.rb`, find the `perform_later` call and add action_id:
```ruby
ProcessUrlEpisodeJob.perform_later(episode_id: episode.id, user_id: user.id, action_id: Current.action_id)
```

In `app/services/create_paste_episode.rb`:
```ruby
ProcessPasteEpisodeJob.perform_later(episode_id: episode.id, user_id: user.id, action_id: Current.action_id)
```

In `app/services/create_file_episode.rb`:
```ruby
ProcessFileEpisodeJob.perform_later(episode_id: episode.id, user_id: user.id, action_id: Current.action_id)
```

In `app/controllers/episodes_controller.rb`, find DeleteEpisodeJob.perform_later and add:
```ruby
DeleteEpisodeJob.perform_later(episode: @episode, action_id: Current.action_id)
```

**Commit message**:
```
feat: propagate action_id through background jobs

Jobs now accept action_id parameter and restore it to Current.action_id
when executing, enabling end-to-end request tracing through async
processing.
```

---

### Task 5: Convert GenerateEpisodeAudio to use EpisodeLogging (#7)

**Files to modify**:
- `app/services/generate_episode_audio.rb`

**Update** `app/services/generate_episode_audio.rb`:
```ruby
# frozen_string_literal: true

require "tempfile"
require "mp3info"

class GenerateEpisodeAudio
  include EpisodeLogging

  def self.call(episode:, skip_feed_upload: false)
    new(episode: episode, skip_feed_upload: skip_feed_upload).call
  end

  def initialize(episode:, skip_feed_upload: false)
    @episode = episode
    @skip_feed_upload = skip_feed_upload
    @uploaded_audio_path = nil
  end

  def call
    log_info "generate_episode_audio_started"

    @episode.update!(status: :processing)

    log_info "synthesizing_audio", voice: voice_name, text_bytes: content_text.bytesize
    audio_content = synthesize_audio

    gcs_episode_id = generate_episode_id
    log_info "uploading_audio", gcs_episode_id: gcs_episode_id, audio_bytes: audio_content.bytesize
    upload_audio(audio_content, gcs_episode_id)

    log_info "calculating_duration"
    duration_seconds = calculate_duration(audio_content)

    log_info "updating_episode", duration_seconds: duration_seconds
    @episode.update!(
      status: :complete,
      gcs_episode_id: gcs_episode_id,
      audio_size_bytes: audio_content.bytesize,
      duration_seconds: duration_seconds
    )

    unless @skip_feed_upload
      log_info "uploading_feed"
      upload_feed
    end

    log_info "generate_episode_audio_completed", gcs_episode_id: gcs_episode_id

    log_info "notifying_user"
    notify_user
  rescue StandardError => e
    log_error "generate_episode_audio_failed", error: e.class, message: e.message
    cleanup_orphaned_audio
    @episode.update!(status: :failed, error_message: e.message)
  end

  private

  attr_reader :episode

  def synthesize_audio
    config = Tts::Config.new(voice_name: voice_name)
    synthesizer = SynthesizesAudio.new(config: config)
    synthesizer.call(text: content_text, voice: voice_name)
  end

  def voice_name
    @episode.voice
  end

  def content_text
    @episode.source_text || ""
  end

  def generate_episode_id
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    slug = @episode.title.downcase
                   .gsub(/[^a-z0-9\s-]/, "")
                   .gsub(/\s+/, "-")
                   .gsub(/-+/, "-")
                   .strip
    "#{timestamp}-#{slug}"
  end

  def upload_audio(audio_content, gcs_episode_id)
    @uploaded_audio_path = "episodes/#{gcs_episode_id}.mp3"
    cloud_storage.upload_content(
      content: audio_content,
      remote_path: @uploaded_audio_path
    )
  end

  def calculate_duration(audio_content)
    Tempfile.create(["episode", ".mp3"]) do |temp_file|
      temp_file.binmode
      temp_file.write(audio_content)
      temp_file.close
      Mp3Info.open(temp_file.path) { |mp3| mp3.length.round }
    end
  rescue StandardError => e
    log_warn "duration_calculation_failed", error: e.message
    nil
  end

  def upload_feed
    feed_xml = GenerateRssFeed.call(podcast: @episode.podcast)
    cloud_storage.upload_content(content: feed_xml, remote_path: "feed.xml")
  end

  def cloud_storage
    @cloud_storage ||= CloudStorage.new(podcast_id: @episode.podcast.podcast_id)
  end

  def notify_user
    NotifiesEpisodeCompletion.call(episode: @episode) if @episode.user&.email_address.present?
  rescue StandardError => e
    log_warn "notification_failed", error: e.message
  end

  def cleanup_orphaned_audio
    return unless @uploaded_audio_path

    log_info "cleaning_up_orphaned_audio", path: @uploaded_audio_path
    cloud_storage.delete_file(remote_path: @uploaded_audio_path)
  rescue StandardError => e
    log_warn "cleanup_failed", error: e.message
  end
end
```

**Commit message**:
```
refactor: GenerateEpisodeAudio now uses EpisodeLogging concern

Replaces manual Rails.logger calls with structured logging via
EpisodeLogging concern for consistent log format and automatic
episode_id/action_id inclusion.
```

---

### Task 6: Convert TTS module to use StructuredLogging

**Files to modify**:
- `app/services/synthesizes_audio.rb`
- `app/services/tts/api_client.rb`
- `app/services/tts/chunked_synthesizer.rb`
- `app/services/tts/text_chunker.rb`

**Update** `app/services/synthesizes_audio.rb`:
```ruby
# frozen_string_literal: true

require_relative "tts/config"
require_relative "tts/api_client"
require_relative "tts/text_chunker"
require_relative "tts/chunked_synthesizer"

class SynthesizesAudio
  include StructuredLogging

  def initialize(config: Tts::Config.new)
    @config = config
    @api_client = Tts::ApiClient.new(config: config)
    @text_chunker = Tts::TextChunker.new
    @chunked_synthesizer = Tts::ChunkedSynthesizer.new(api_client: @api_client, config: config)
  end

  def call(text:, voice: nil)
    log_info "tts_generation_started"
    voice ||= @config.voice_name

    chunks = @text_chunker.chunk(text, @config.byte_limit)

    audio_content = if chunks.length == 1
                      @api_client.call(text: chunks[0], voice: voice)
    else
                      @chunked_synthesizer.synthesize(chunks, voice)
    end

    log_info "tts_generation_completed", audio_bytes: audio_content.bytesize
    audio_content
  end

  private

  def format_size(bytes)
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end
end
```

**Update** `app/services/tts/api_client.rb`:
```ruby
# frozen_string_literal: true

require "google/cloud/text_to_speech"

module Tts
  class ApiClient
    include StructuredLogging

    def initialize(config:)
      @config = config
      @client = Google::Cloud::TextToSpeech.text_to_speech do |client_config|
        client_config.timeout = @config.timeout
      end
    end

    def call(text:, voice:)
      max_retries = @config.max_retries
      retries = 0

      begin
        make_request(text: text, voice: voice)
      rescue Google::Cloud::ResourceExhaustedError
        raise unless retries < max_retries

        retries += 1
        wait_time = 2**retries
        log_warn "tts_rate_limit_hit", wait_seconds: wait_time, retry: retries, max_retries: max_retries
        sleep(wait_time)
        retry
      rescue Google::Cloud::Error => e
        safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        raise unless retries < max_retries && safe_message.include?(Tts::Constants::DEADLINE_EXCEEDED_ERROR)

        retries += 1
        log_warn "tts_timeout", retry: retries, max_retries: max_retries
        sleep(1)
        retry
      end
    end

    private

    def make_request(text:, voice:)
      log_info "tts_api_call_started", bytes: text.bytesize, voice: voice

      response = @client.synthesize_speech(
        input: { text: text },
        voice: build_voice_params(voice),
        audio_config: build_audio_config
      )

      log_info "tts_api_call_completed", audio_bytes: response.audio_content.bytesize
      response.audio_content
    rescue StandardError => e
      safe_message = e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      log_error "tts_api_call_failed", error: safe_message
      raise
    end

    def build_voice_params(voice)
      {
        language_code: @config.language_code,
        name: voice
      }
    end

    def build_audio_config
      {
        audio_encoding: @config.audio_encoding,
        speaking_rate: @config.speaking_rate,
        pitch: @config.pitch
      }
    end
  end
end
```

**Update** `app/services/tts/chunked_synthesizer.rb`:
```ruby
# frozen_string_literal: true

require "concurrent"

module Tts
  class ChunkedSynthesizer
    include StructuredLogging

    def initialize(api_client:, config:)
      @api_client = api_client
      @config = config
    end

    def synthesize(chunks, voice)
      return "" if chunks.empty?

      log_synthesis_start(chunks)

      start_time = Time.now
      pool = Concurrent::FixedThreadPool.new(@config.thread_pool_size)
      promises = launch_chunk_promises(chunks: chunks, voice: voice, pool: pool)

      results = wait_for_completion(promises)
      audio_parts = extract_audio_parts(results)

      cleanup_pool(pool)
      log_synthesis_complete(chunks: chunks, audio_parts: audio_parts, start_time: start_time)

      audio_parts.join
    end

    private

    def log_synthesis_start(chunks)
      log_info "tts_chunked_synthesis_started",
        chunk_count: chunks.length,
        thread_pool_size: @config.thread_pool_size,
        chunk_sizes: chunks.map(&:bytesize).join(",")
    end

    def launch_chunk_promises(chunks:, voice:, pool:)
      skipped_chunks = Concurrent::Array.new
      promises = []
      total = chunks.length

      chunks.each_with_index do |chunk, i|
        promise = Concurrent::Promise.execute(executor: pool) do
          process_chunk(chunk: chunk, index: i, total: total, voice: voice, skipped_chunks: skipped_chunks)
        end
        promises << promise
      end

      @skipped_chunks = skipped_chunks
      promises
    end

    def process_chunk(chunk:, index:, total:, voice:, skipped_chunks:)
      chunk_num = index + 1
      log_info "tts_chunk_started", chunk: chunk_num, total: total, bytes: chunk.bytesize

      chunk_start = Time.now
      audio = synthesize_chunk_with_error_handling(chunk: chunk, chunk_num: chunk_num, total: total, voice: voice,
                                                   skipped_chunks: skipped_chunks)

      log_chunk_completion(chunk_num: chunk_num, total: total, chunk_start: chunk_start) if audio

      [index, audio]
    end

    def synthesize_chunk_with_error_handling(chunk:, chunk_num:, total:, voice:, skipped_chunks:)
      @api_client.call(text: chunk, voice: voice)
    rescue StandardError => e
      handle_chunk_error(error: e, chunk_num: chunk_num, total: total, skipped_chunks: skipped_chunks)
      nil
    end

    def handle_chunk_error(error:, chunk_num:, total:, skipped_chunks:)
      safe_message = error.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

      if safe_message.include?(Tts::Constants::CONTENT_FILTER_ERROR)
        log_warn "tts_chunk_skipped", chunk: chunk_num, total: total, reason: "content_filter"
        skipped_chunks << chunk_num
      else
        log_error "tts_chunk_failed", chunk: chunk_num, total: total, error: safe_message
        raise
      end
    end

    def log_chunk_completion(chunk_num:, total:, chunk_start:)
      chunk_duration = Time.now - chunk_start
      log_info "tts_chunk_completed", chunk: chunk_num, total: total, duration_seconds: chunk_duration.round(2)
    end

    def wait_for_completion(promises)
      log_info "tts_waiting_for_chunks"
      promises.map(&:value!)
    end

    def extract_audio_parts(results)
      results
        .compact
        .sort_by { |idx, _| idx }
        .map { |_, audio| audio }
        .compact
    end

    def cleanup_pool(pool)
      pool.shutdown
      pool.wait_for_termination
    end

    def log_synthesis_complete(chunks:, audio_parts:, start_time:)
      total_duration = Time.now - start_time

      if @skipped_chunks.any?
        log_warn "tts_chunks_skipped",
          skipped_count: @skipped_chunks.length,
          skipped_chunks: @skipped_chunks.sort.join(",")
      end

      log_info "tts_chunked_synthesis_completed",
        chunks_processed: audio_parts.length,
        chunks_total: chunks.length,
        duration_seconds: total_duration.round(2)
    end
  end
end
```

**Update** `app/services/tts/text_chunker.rb:74`:
```ruby
# Add include at top of class
include StructuredLogging

# Replace line 74:
# Before
Rails.logger.warn "[TTS] Single word exceeds max_bytes: #{word[0..20]}... (#{word.bytesize} bytes)"

# After
log_warn "tts_word_exceeds_max_bytes", word_preview: word[0..20], bytes: word.bytesize
```

**Commit message**:
```
refactor: convert TTS module to use StructuredLogging

Replaces [TTS] prefix logging with structured event logging throughout
SynthesizesAudio, Tts::ApiClient, Tts::ChunkedSynthesizer, and
Tts::TextChunker for consistent log format and traceability.
```

---

### Task 7: Audit and convert remaining services with Rails.logger

**Files to audit and potentially modify**:
- `app/services/create_url_episode.rb`
- `app/services/create_paste_episode.rb`
- `app/services/create_file_episode.rb`
- `app/services/syncs_subscription.rb`
- `app/services/submit_episode_for_processing.rb`
- `app/services/create_user.rb`
- `app/services/authenticate_magic_link.rb`
- `app/services/processes_with_llm.rb`
- `app/services/fetches_url.rb`
- `app/services/extracts_article.rb`
- `app/services/record_llm_usage.rb`
- `app/services/asks_llm.rb`
- `app/services/invalidate_auth_token.rb`
- `app/services/delete_episode.rb`

For each file with `Rails.logger`:
1. Add `include StructuredLogging` (or `include EpisodeLogging` if it has an episode)
2. Replace `Rails.logger.info "event=X ..."` with `log_info "X", ...`
3. Replace `Rails.logger.warn` with `log_warn`
4. Replace `Rails.logger.error` with `log_error`

**Commit message**:
```
refactor: convert remaining services to use StructuredLogging

Standardizes all service logging to use StructuredLogging concern,
ensuring consistent event=X key=value format with action_id tracing
throughout the codebase.
```

---

## PR2 Verification

```bash
rake test
bundle exec rubocop
```

**Manual verification**:
- Create episode from URL
- Check logs for `action_id=` present in all log lines
- Trace from controller through job to completion
- Verify format: `event=X action_id=Y episode_id=Z key=value`

---

## Create PR2

```bash
git checkout main && git pull
git checkout -b refactor/structured-logging
# ... make commits ...
git push -u origin refactor/structured-logging
gh pr create --title "Refactor: Structured logging with action_id tracing" --body "$(cat <<'EOF'
## Summary

Implements consistent structured logging across the entire codebase:

- **New `StructuredLogging` concern**: Base logging with `event=X key=value` format
- **Refactored `EpisodeLogging`**: Now extends StructuredLogging, adds episode_id
- **Action ID tracing**: Request ID flows from controller through jobs for end-to-end tracing
- **TTS module converted**: Replaces `[TTS]` prefix with structured events
- **All services audited**: Consistent logging throughout

### Log format

```
event=process_url_episode_started action_id=abc-123 episode_id=456 url=https://...
```

## Test plan

- [ ] All existing tests pass
- [ ] Create episode from URL
- [ ] Verify logs contain action_id throughout
- [ ] Trace a request from controller → job → service → TTS
EOF
)"
```

---

# PR3: Service Naming Standardization

**Branch**: `refactor/service-naming`
**Base**: `main` (after PR2 merged)

## Services to Rename (24 total)

| Current File | New File | References to Update |
|--------------|----------|----------------------|
| `create_url_episode.rb` | `creates_url_episode.rb` | `app/controllers/episodes_controller.rb`, `test/services/create_url_episode_test.rb` |
| `create_paste_episode.rb` | `creates_paste_episode.rb` | `app/controllers/episodes_controller.rb`, `test/services/create_paste_episode_test.rb` |
| `create_file_episode.rb` | `creates_file_episode.rb` | `app/controllers/episodes_controller.rb`, `test/services/create_file_episode_test.rb` |
| `create_default_podcast.rb` | `creates_default_podcast.rb` | `app/services/create_user.rb`, `app/controllers/episodes_controller.rb`, `test/services/create_default_podcast_test.rb` |
| `create_user.rb` | `creates_user.rb` | `app/services/send_magic_link.rb`, `test/services/create_user_test.rb`, `test/controllers/api/internal/episodes_controller_test.rb` |
| `process_url_episode.rb` | `processes_url_episode.rb` | `app/jobs/process_url_episode_job.rb`, `test/services/process_url_episode_test.rb` |
| `process_paste_episode.rb` | `processes_paste_episode.rb` | `app/jobs/process_paste_episode_job.rb`, `test/services/process_paste_episode_test.rb`, `test/jobs/process_paste_episode_job_test.rb` |
| `process_file_episode.rb` | `processes_file_episode.rb` | `app/jobs/process_file_episode_job.rb`, `test/services/process_file_episode_test.rb`, `test/jobs/process_file_episode_job_test.rb` |
| `delete_episode.rb` | `deletes_episode.rb` | `app/jobs/delete_episode_job.rb`, `test/services/delete_episode_test.rb` |
| `generate_episode_audio.rb` | `generates_episode_audio.rb` | `app/services/submit_episode_for_processing.rb`, `test/services/generate_episode_audio_test.rb`, `test/services/submit_episode_for_processing_test.rb` |
| `generate_episode_download_url.rb` | `generates_episode_download_url.rb` | `app/models/episode.rb`, `test/services/generate_episode_download_url_test.rb` |
| `generate_rss_feed.rb` | `generates_rss_feed.rb` | `app/services/generate_episode_audio.rb`, `app/services/delete_episode.rb`, `test/services/generate_rss_feed_test.rb`, `test/controllers/episodes_controller_test.rb`, `test/services/delete_episode_test.rb` |
| `generate_auth_token.rb` | `generates_auth_token.rb` | `app/services/send_magic_link.rb`, `test/services/generate_auth_token_test.rb`, `test/services/send_magic_link_test.rb`, `test/services/authenticate_magic_link_test.rb`, `test/mailers/sessions_mailer_test.rb`, `test/controllers/sessions_controller_test.rb`, `test/controllers/concerns/trackable_test.rb`, `test/controllers/admin/analytics_controller_test.rb`, `app/controllers/test_helpers_controller.rb` |
| `validate_auth_token.rb` | `validates_auth_token.rb` | `test/services/validate_auth_token_test.rb` |
| `invalidate_auth_token.rb` | `invalidates_auth_token.rb` | `app/services/authenticate_magic_link.rb`, `test/services/invalidate_auth_token_test.rb` |
| `send_magic_link.rb` | `sends_magic_link.rb` | `app/controllers/sessions_controller.rb`, `test/services/send_magic_link_test.rb` |
| `record_episode_usage.rb` | `records_episode_usage.rb` | `app/controllers/episodes_controller.rb`, `test/services/record_episode_usage_test.rb` |
| `record_sent_message.rb` | `records_sent_message.rb` | `app/services/notifies_episode_completion.rb`, `test/services/record_sent_message_test.rb` |
| `record_llm_usage.rb` | `records_llm_usage.rb` | `app/services/processes_with_llm.rb`, `test/services/record_llm_usage_test.rb`, `test/services/processes_with_llm_test.rb` |
| `refund_episode_usage.rb` | `refunds_episode_usage.rb` | `app/controllers/api/internal/episodes_controller.rb`, `test/services/refund_episode_usage_test.rb` |
| `submit_episode_for_processing.rb` | `submits_episode_for_processing.rb` | `app/services/process_url_episode.rb`, `app/services/process_paste_episode.rb`, `app/services/process_file_episode.rb`, `test/services/submit_episode_for_processing_test.rb`, `test/services/process_url_episode_test.rb`, `test/services/process_paste_episode_test.rb`, `test/services/process_file_episode_test.rb`, `test/integration/paste_episode_flow_test.rb` |
| `verify_hashed_token.rb` | `verifies_hashed_token.rb` | `app/services/authenticate_magic_link.rb`, `test/services/verify_hashed_token_test.rb` |
| `authenticate_magic_link.rb` | `authenticates_magic_link.rb` | `app/controllers/sessions_controller.rb`, `test/services/authenticate_magic_link_test.rb` |
| `build_episode_wrapper.rb` | `builds_episode_wrapper.rb` | `app/services/submit_episode_for_processing.rb`, `test/services/build_episode_wrapper_test.rb` |

## Jobs to Rename (3 total)

| Current File | New File | References to Update |
|--------------|----------|----------------------|
| `process_url_episode_job.rb` | `processes_url_episode_job.rb` | `app/services/create_url_episode.rb`, `test/jobs/process_url_episode_job_test.rb` |
| `process_paste_episode_job.rb` | `processes_paste_episode_job.rb` | `app/services/create_paste_episode.rb`, `test/jobs/process_paste_episode_job_test.rb` |
| `process_file_episode_job.rb` | `processes_file_episode_job.rb` | `app/services/create_file_episode.rb`, `test/jobs/process_file_episode_job_test.rb` |

## Additional files to update

- `README.md` - references `CreateUrlEpisode`
- `Agents.md` - references `CreateUrlEpisode`, `ProcessUrlEpisode`

## Rename Procedure

For each service/job:

1. `git mv app/services/create_url_episode.rb app/services/creates_url_episode.rb`
2. Update class name inside the file: `class CreateUrlEpisode` → `class CreatesUrlEpisode`
3. Update all references in files listed above
4. Update corresponding test file name and class references

## Suggested Commit Strategy

Break into logical groups:

**Commit 1**: Rename Create* services
```
refactor: rename Create* services to Creates* (third-person verb)

- CreateUrlEpisode → CreatesUrlEpisode
- CreatePasteEpisode → CreatesPasteEpisode
- CreateFileEpisode → CreatesFileEpisode
- CreateDefaultPodcast → CreatesDefaultPodcast
- CreateUser → CreatesUser
```

**Commit 2**: Rename Process* services and jobs
```
refactor: rename Process* services and jobs to Processes*

- ProcessUrlEpisode → ProcessesUrlEpisode
- ProcessPasteEpisode → ProcessesPasteEpisode
- ProcessFileEpisode → ProcessesFileEpisode
- ProcessUrlEpisodeJob → ProcessesUrlEpisodeJob
- ProcessPasteEpisodeJob → ProcessesPasteEpisodeJob
- ProcessFileEpisodeJob → ProcessesFileEpisodeJob
```

**Commit 3**: Rename Generate* services
```
refactor: rename Generate* services to Generates*

- GenerateEpisodeAudio → GeneratesEpisodeAudio
- GenerateEpisodeDownloadUrl → GeneratesEpisodeDownloadUrl
- GenerateRssFeed → GeneratesRssFeed
- GenerateAuthToken → GeneratesAuthToken
```

**Commit 4**: Rename remaining services
```
refactor: rename remaining services to third-person verb form

- DeleteEpisode → DeletesEpisode
- ValidateAuthToken → ValidatesAuthToken
- InvalidateAuthToken → InvalidatesAuthToken
- SendMagicLink → SendsMagicLink
- RecordEpisodeUsage → RecordsEpisodeUsage
- RecordSentMessage → RecordsSentMessage
- RecordLlmUsage → RecordsLlmUsage
- RefundEpisodeUsage → RefundsEpisodeUsage
- SubmitEpisodeForProcessing → SubmitsEpisodeForProcessing
- VerifyHashedToken → VerifiesHashedToken
- AuthenticateMagicLink → AuthenticatesMagicLink
- BuildEpisodeWrapper → BuildsEpisodeWrapper
```

---

## PR3 Verification

```bash
rake test
bundle exec rubocop

# Verify no old references remain
grep -r "CreateUrlEpisode" app/ test/ --include="*.rb" | grep -v "Creates"
grep -r "ProcessUrlEpisode" app/ test/ --include="*.rb" | grep -v "Processes"
# ... etc for each renamed service
```

---

## Create PR3

```bash
git checkout main && git pull
git checkout -b refactor/service-naming
# ... make commits ...
git push -u origin refactor/service-naming
gh pr create --title "Refactor: Standardize service naming to third-person verbs" --body "$(cat <<'EOF'
## Summary

Standardizes all service class names to use third-person verb form for consistency:

- `CreateUrlEpisode` → `CreatesUrlEpisode`
- `ProcessUrlEpisode` → `ProcessesUrlEpisode`
- `GenerateEpisodeAudio` → `GeneratesEpisodeAudio`
- ... (24 services + 3 jobs total)

This aligns with the existing majority pattern in the codebase (e.g., `ValidatesUrl`, `FetchesUrl`, `SynthesizesAudio`).

## Test plan

- [ ] All tests pass
- [ ] Grep for old class names returns no results
- [ ] Create episode from URL - full flow works
- [ ] Create episode from paste - full flow works
EOF
)"
```

---

## Summary

| PR | Branch | Commits | Key Changes |
|----|--------|---------|-------------|
| PR1 | `refactor/quick-wins` | 4 | AppConfig constant, FormatsDuration, ValidatesUrl API, keyword args |
| PR2 | `refactor/structured-logging` | 7 | StructuredLogging, EpisodeLogging refactor, action_id, TTS conversion, audit |
| PR3 | `refactor/service-naming` | 4 | Rename 24 services + 3 jobs |

**Execution order**: PR1 → merge → PR2 → merge → PR3 → merge
