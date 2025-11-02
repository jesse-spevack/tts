# Wave 2: Podcast Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform storage from flat structure to podcast-scoped isolation (`podcasts/{podcast_id}/`) with Firestore user mapping for future multi-user support.

**Architecture:**
- Storage: `podcasts/{podcast_id}/episodes/`, `feed.xml`, `manifest.json`, `staging/`
- Firestore: User → podcast_id mapping, podcast ownership tracking
- Local usage: `generate.rb` uses `PODCAST_ID` env var
- API: Updated to accept `podcast_id` parameter

**Tech Stack:** Ruby 3.4, Google Cloud Storage, Google Cloud Firestore, Sinatra 4.0

**Fast Follows (Next Steps):**
1. **Cost tracking**: Add structured logging for TTS costs, storage costs per episode
2. **Episode cleanup tooling**: Script to delete unwanted test episodes from GCS
3. **Episode rename tooling**: Script to rename episodes and update manifest
4. **IAM authentication**: Remove API_SECRET_TOKEN, add service-to-service auth (when Web UI is ready)

---

## Task 1: Add Firestore Client Wrapper

**Files:**
- Create: `lib/firestore_client.rb`
- Create: `test/test_firestore_client.rb`

**Step 1: Write the failing test**

Create `test/test_firestore_client.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/firestore_client"

class TestFirestoreClient < Minitest::Test
  def setup
    @client = FirestoreClient.new
  end

  def test_initializes_with_project_id_from_env
    assert_instance_of FirestoreClient, @client
  end

  def test_get_user_podcast_id_returns_podcast_id
    # This test will use mocking in implementation
    skip "Integration test - requires Firestore emulator or mock"
  end

  def test_get_podcast_owner_returns_user_id
    skip "Integration test - requires Firestore emulator or mock"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby test/test_firestore_client.rb`
Expected: FAIL with "cannot load such file -- ../lib/firestore_client"

**Step 3: Write minimal implementation**

Create `lib/firestore_client.rb`:

```ruby
require "google/cloud/firestore"

class FirestoreClient
  class UserNotFoundError < StandardError; end
  class PodcastNotFoundError < StandardError; end

  def initialize(project_id = nil)
    @project_id = project_id || ENV.fetch("GOOGLE_CLOUD_PROJECT")
    @firestore = nil
  end

  # Get user's podcast_id from Firestore
  # @param user_id [String] User identifier
  # @return [String] Podcast ID
  # @raise [UserNotFoundError] If user document doesn't exist
  def get_user_podcast_id(user_id)
    doc = firestore.col("users").doc(user_id).get
    raise UserNotFoundError, "User #{user_id} not found" unless doc.exists?

    podcast_id = doc.data[:podcast_id]
    raise UserNotFoundError, "User #{user_id} has no podcast_id" unless podcast_id

    podcast_id
  end

  # Get podcast owner user_id from Firestore
  # @param podcast_id [String] Podcast identifier
  # @return [String] User ID who owns the podcast
  # @raise [PodcastNotFoundError] If podcast document doesn't exist
  def get_podcast_owner(podcast_id)
    doc = firestore.col("podcasts").doc(podcast_id).get
    raise PodcastNotFoundError, "Podcast #{podcast_id} not found" unless doc.exists?

    owner_user_id = doc.data[:owner_user_id]
    raise PodcastNotFoundError, "Podcast #{podcast_id} has no owner" unless owner_user_id

    owner_user_id
  end

  private

  def firestore
    @firestore ||= Google::Cloud::Firestore.new(project_id: @project_id)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby test/test_firestore_client.rb`
Expected: PASS (tests are skipped, but class loads)

**Step 5: Update Gemfile**

Add Firestore gem to `Gemfile`:

```ruby
gem "google-cloud-firestore", "~> 2.0"
```

Run: `bundle install`

**Step 6: Run RuboCop**

Run: `rake rubocop`
Expected: PASS with no offenses

**Step 7: Commit**

```bash
git add lib/firestore_client.rb test/test_firestore_client.rb Gemfile Gemfile.lock
git commit -m "feat: add Firestore client for user/podcast mapping"
```

---

## Task 2: Add podcast_id path scoping to GCSUploader

**Files:**
- Modify: `lib/gcs_uploader.rb`
- Modify: `test/test_gcs_uploader.rb`

**Step 1: Write the failing test**

Add to `test/test_gcs_uploader.rb`:

```ruby
def test_scoped_path_prepends_podcast_id
  uploader = GCSUploader.new("my-bucket", podcast_id: "podcast_123")
  scoped = uploader.scoped_path("episodes/test.mp3")

  assert_equal "podcasts/podcast_123/episodes/test.mp3", scoped
end

def test_scoped_path_without_podcast_id_returns_original
  uploader = GCSUploader.new("my-bucket")
  scoped = uploader.scoped_path("episodes/test.mp3")

  assert_equal "episodes/test.mp3", scoped
end

def test_get_public_url_uses_scoped_path
  uploader = GCSUploader.new("my-bucket", podcast_id: "podcast_123")
  url = uploader.get_public_url(remote_path: "feed.xml")

  assert_equal "https://storage.googleapis.com/my-bucket/podcasts/podcast_123/feed.xml", url
end
```

**Step 2: Run test to verify it fails**

Run: `ruby test/test_gcs_uploader.rb`
Expected: FAIL with "wrong number of arguments"

**Step 3: Implement podcast_id scoping**

Modify `lib/gcs_uploader.rb`:

```ruby
class GCSUploader
  class MissingBucketError < StandardError; end
  class MissingCredentialsError < StandardError; end
  class UploadError < StandardError; end

  attr_reader :bucket_name, :podcast_id

  # Initialize GCS uploader with bucket name and optional podcast_id
  # @param bucket_name [String] Name of the GCS bucket
  # @param podcast_id [String, nil] Optional podcast ID for path scoping
  def initialize(bucket_name, podcast_id: nil)
    raise MissingBucketError, "Bucket name cannot be nil or empty" if bucket_name.nil? || bucket_name.empty?

    @bucket_name = bucket_name
    @podcast_id = podcast_id
    @storage = nil
  end

  # Generate scoped path with podcast_id prefix if present
  # @param path [String] Original path
  # @return [String] Scoped path
  def scoped_path(path)
    return path unless @podcast_id

    "podcasts/#{@podcast_id}/#{path}"
  end

  # Upload a file to Google Cloud Storage and make it publicly accessible
  # @param local_path [String] Path to local file
  # @param remote_path [String] Destination path in GCS bucket (will be scoped if podcast_id present)
  # @return [String] Public URL of the uploaded file
  def upload_file(local_path:, remote_path:)
    raise UploadError, "Local file does not exist: #{local_path}" unless File.exist?(local_path)

    begin
      scoped_remote_path = scoped_path(remote_path)
      file = bucket.create_file(local_path, scoped_remote_path)
      file.acl.public!
      get_public_url(remote_path: remote_path)
    rescue Google::Cloud::Error => e
      raise UploadError, "Failed to upload file: #{e.message}"
    end
  end

  # Upload content directly to GCS (for JSON, XML, etc.)
  # @param content [String] Content to upload
  # @param remote_path [String] Destination path in GCS bucket (will be scoped if podcast_id present)
  # @return [String] Public URL of the uploaded content
  def upload_content(content:, remote_path:)
    scoped_remote_path = scoped_path(remote_path)

    # Upload the file
    file = bucket.create_file(StringIO.new(content), scoped_remote_path)
    file.acl.public!

    # Set cache control for RSS feeds to prevent stale content
    file.cache_control = "no-cache, max-age=0" if remote_path == "feed.xml"

    get_public_url(remote_path: remote_path)
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to upload content: #{e.message}"
  end

  # Download file content from GCS
  # @param remote_path [String] Path to file in GCS bucket (will be scoped if podcast_id present)
  # @return [String] File content as string with UTF-8 encoding
  def download_file(remote_path:)
    scoped_remote_path = scoped_path(remote_path)
    file = bucket.file(scoped_remote_path)
    raise UploadError, "File not found: #{scoped_remote_path}" unless file

    # Force UTF-8 encoding to prevent ASCII-8BIT encoding issues
    file.download.read.force_encoding("UTF-8")
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to download file: #{e.message}"
  end

  # Delete a file from GCS
  # @param remote_path [String] Path to file in GCS bucket (will be scoped if podcast_id present)
  # @return [Boolean] True if deleted, false if file didn't exist
  def delete_file(remote_path:)
    scoped_remote_path = scoped_path(remote_path)
    file = bucket.file(scoped_remote_path)
    return false unless file

    file.delete
    true
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to delete file: #{e.message}"
  end

  # Get public URL for a file in the bucket
  # @param remote_path [String] Path to file in GCS bucket (will be scoped if podcast_id present)
  # @return [String] Public HTTPS URL
  def get_public_url(remote_path:)
    scoped_remote_path = scoped_path(remote_path)
    # Remove leading slash if present
    path = scoped_remote_path.start_with?("/") ? scoped_remote_path[1..] : scoped_remote_path
    "https://storage.googleapis.com/#{bucket_name}/#{path}"
  end

  private

  # Lazy-load storage client
  def storage
    @storage ||= begin
      # On Cloud Run, credentials are automatic via service account
      # Only check for GOOGLE_APPLICATION_CREDENTIALS in local/test environments
      if !ENV["GOOGLE_APPLICATION_CREDENTIALS"] && ENV["RACK_ENV"] != "production"
        raise MissingCredentialsError,
              "GOOGLE_APPLICATION_CREDENTIALS not set"
      end

      Google::Cloud::Storage.new
    rescue Google::Cloud::Error => e
      raise MissingCredentialsError, "Failed to initialize Google Cloud Storage: #{e.message}"
    end
  end

  # Get bucket object
  def bucket
    @bucket ||= begin
      b = storage.bucket(bucket_name)
      raise UploadError, "Bucket '#{bucket_name}' not found" unless b

      b
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby test/test_gcs_uploader.rb`
Expected: PASS

**Step 5: Run all tests**

Run: `rake test`
Expected: All tests pass

**Step 6: Run RuboCop**

Run: `rake rubocop`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/gcs_uploader.rb test/test_gcs_uploader.rb
git commit -m "feat: add podcast_id scoping to GCS paths"
```

---

## Task 3: Update generate.rb to use PODCAST_ID

**Files:**
- Modify: `generate.rb`
- Modify: `.env.example`

**Step 1: Update .env.example**

Add to `.env.example`:

```bash
# Podcast ID for isolated storage (required for Wave 2+)
# Format: podcast_{random_id}
# Example: PODCAST_ID=podcast_abc123xyz
PODCAST_ID=your-podcast-id-here
```

**Step 2: Update generate.rb to pass podcast_id**

Modify `generate.rb` around line 119:

```ruby
# Initialize GCS and manifest
podcast_id = ENV.fetch("PODCAST_ID", nil)
gcs_uploader = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
episode_manifest = EpisodeManifest.new(gcs_uploader)
```

**Step 3: Test local generation**

First, set PODCAST_ID in your `.env`:
```bash
PODCAST_ID=podcast_test_123
```

Run: `ruby generate.rb input/sample.md`
Expected: Episode published to `podcasts/podcast_test_123/episodes/`, `feed.xml`, `manifest.json`

**Step 4: Verify GCS structure**

Run: `gsutil ls -r gs://YOUR_BUCKET/podcasts/podcast_test_123/`
Expected: See episodes/, feed.xml, manifest.json under podcast-scoped path

**Step 5: Commit**

```bash
git add generate.rb .env.example
git commit -m "feat: update generate.rb to use PODCAST_ID for scoped storage"
```

---

## Task 4: Update EpisodeProcessor to use podcast_id

**Files:**
- Modify: `lib/episode_processor.rb`
- Modify: `test/test_episode_processor.rb`

**Step 1: Write the failing test**

Modify `test/test_episode_processor.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/episode_processor"

class TestEpisodeProcessor < Minitest::Test
  def test_initializes_with_bucket_name_and_podcast_id
    processor = EpisodeProcessor.new("test-bucket", "podcast_123")
    assert_instance_of EpisodeProcessor, processor
    assert_equal "test-bucket", processor.bucket_name
    assert_equal "podcast_123", processor.podcast_id
  end

  def test_raises_error_without_podcast_id
    error = assert_raises(ArgumentError) do
      EpisodeProcessor.new("test-bucket", nil)
    end
    assert_match(/podcast_id is required/, error.message)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby test/test_episode_processor.rb`
Expected: FAIL with "wrong number of arguments"

**Step 3: Update EpisodeProcessor constructor**

Modify `lib/episode_processor.rb`:

```ruby
class EpisodeProcessor
  attr_reader :bucket_name, :podcast_id

  def initialize(bucket_name = nil, podcast_id = nil)
    @bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET")
    @podcast_id = podcast_id

    raise ArgumentError, "podcast_id is required" unless @podcast_id
  end

  # Process an episode from start to finish
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def process(title, author, description, markdown_content)
    print_start(title)
    filename = FilenameGenerator.generate(title)
    mp3_path = nil

    begin
      # Step 1: Convert markdown to plain text
      text = TextProcessor.convert_to_plain_text(markdown_content)
      puts "✓ Converted to #{text.length} characters of plain text"

      # Step 2: Generate TTS audio
      puts "\n[2/4] Generating TTS audio..."
      tts = TTS.new
      audio_content = tts.synthesize(text)
      puts "✓ Generated #{format_size(audio_content.bytesize)} of audio"

      # Step 3: Save MP3 temporarily
      mp3_path = save_temp_mp3(filename, audio_content)

      # Step 4: Publish to podcast feed
      publish_to_feed(mp3_path, title, author, description)

      print_success(title)
    ensure
      # Always cleanup temporary file
      cleanup_temp_file(mp3_path) if mp3_path
    end
  end

  private

  def save_temp_mp3(filename, audio_content)
    puts "\n[3/4] Saving temporary MP3..."

    FileUtils.mkdir_p("output")
    path = File.join("output", "#{filename}.mp3")
    File.write(path, audio_content, mode: "wb")

    puts "✓ Saved: #{path}"

    path
  end

  def publish_to_feed(mp3_path, title, author, description)
    puts "\n[4/4] Publishing to feed..."

    podcast_config = YAML.safe_load_file("config/podcast.yml")
    gcs_uploader = GCSUploader.new(@bucket_name, podcast_id: @podcast_id)
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    publisher.publish(mp3_path, metadata(title: title, author: author, description: description))

    puts "✓ Published"
  end

  def metadata(title:, author:, description:)
    {
      "title" => title,
      "author" => author,
      "description" => description
    }
  end

  def cleanup_temp_file(path)
    FileUtils.rm_f(path)
    puts "✓ Cleaned up: #{path}"
  rescue StandardError => e
    puts "⚠ Cleanup warning: #{e.message}"
  end

  def format_size(bytes)
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end

  def print_start(title)
    puts "=" * 60
    puts "Processing: #{title}"
    puts "=" * 60
  end

  def print_success(title)
    puts "\n#{'=' * 60}"
    puts "✓ Complete: #{title}"
    puts "=" * 60
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby test/test_episode_processor.rb`
Expected: PASS

**Step 5: Run all tests**

Run: `rake test`
Expected: All tests pass

**Step 6: Run RuboCop**

Run: `rake rubocop`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/episode_processor.rb test/test_episode_processor.rb
git commit -m "feat: require podcast_id in EpisodeProcessor"
```

---

## Task 5: Update API to accept podcast_id

**Files:**
- Modify: `api.rb`
- Modify: `lib/publish_params_validator.rb`
- Modify: `test/test_api.rb`

**Step 1: Write failing test for podcast_id validation**

Add to `test/test_api.rb`:

```ruby
def test_publish_rejects_missing_podcast_id
  post "/publish",
       { title: "Test", author: "Author", description: "Desc", content: upload_file },
       auth_header

  assert_equal 400, last_response.status
  json = JSON.parse(last_response.body)
  assert_match(/podcast_id/i, json["message"])
end

def test_publish_accepts_podcast_id
  # This will be integration test - skip for now
  skip "Requires full stack"
end
```

**Step 2: Run test to verify it fails**

Run: `ruby test/test_api.rb`
Expected: FAIL - test expects 400 but gets 200

**Step 3: Update PublishParamsValidator**

Modify `lib/publish_params_validator.rb`:

```ruby
class PublishParamsValidator
  def initialize(params)
    @params = params
  end

  def validate
    errors = []
    errors << "Missing podcast_id" unless @params[:podcast_id]
    errors << "Missing title" unless @params[:title]
    errors << "Missing author" unless @params[:author]
    errors << "Missing description" unless @params[:description]
    errors << "Missing content file" unless @params[:content]

    errors
  end
end
```

**Step 4: Update api.rb to use podcast_id**

Modify `api.rb` `/publish` endpoint:

```ruby
# Public endpoint: Accept episode submission
post "/publish" do
  # Step 1: Authenticate
  halt 401, json(status: "error", message: "Unauthorized") unless authenticated?

  # Step 2: Validate required fields
  errors = PublishParamsValidator.new(params).validate
  halt 400, json(status: "error", message: errors.join(", ")) if errors.any?

  # Step 3: Extract parameters
  podcast_id = params[:podcast_id]
  title = params[:title]
  author = params[:author]
  description = params[:description]
  content_file = params[:content]

  # Step 4: Read file content
  markdown_content = content_file[:tempfile].read

  # Step 5: Generate filename and upload to GCS staging
  filename = FilenameGenerator.generate(title)
  staging_path = "staging/#{filename}.md"

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
  gcs.upload_content(content: markdown_content, remote_path: staging_path)

  logger.info "event=file_uploaded podcast_id=#{podcast_id} title=\"#{title}\" staging_path=#{staging_path}"

  # Step 6: Enqueue processing task
  task_payload = {
    podcast_id: podcast_id,
    title: title,
    author: author,
    description: description,
    staging_path: staging_path
  }
  task_name = CloudTasksEnqueuer.new.enqueue_episode_processing(task_payload)
  logger.info "event=task_enqueued podcast_id=#{podcast_id} title=\"#{title}\" task_name=#{task_name}"

  # Step 7: Return success immediately
  logger.info "event=episode_submitted podcast_id=#{podcast_id} title=\"#{title}\""
  json status: "success", message: "Episode submitted for processing"
rescue StandardError => e
  logger.error "Error: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end
```

**Step 5: Update /process endpoint**

Modify `/process` endpoint in `api.rb`:

```ruby
# Internal endpoint: Process episode (triggered by Cloud Tasks)
post "/process" do
  request.body.rewind
  payload = JSON.parse(request.body.read)

  validation_error = validate_task_payload(payload)
  halt 400, json(status: "error", message: validation_error) if validation_error

  process_episode_task(payload)

  json status: "success", message: "Episode processed successfully"
rescue JSON::ParserError => e
  logger.error "Invalid JSON: #{e.message}"
  halt 400, json(status: "error", message: "Invalid JSON payload")
rescue StandardError => e
  logger.error "Processing error: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end

# Helper: Validate task payload
def validate_task_payload(payload)
  return "Missing podcast_id" unless payload["podcast_id"]
  return "Missing title" unless payload["title"]
  return "Missing author" unless payload["author"]
  return "Missing description" unless payload["description"]
  return "Missing staging_path" unless payload["staging_path"]

  nil # No errors
end

# Helper: Process episode from Cloud Task payload
def process_episode_task(payload)
  podcast_id = payload["podcast_id"]
  title = payload["title"]
  author = payload["author"]
  description = payload["description"]
  staging_path = payload["staging_path"]

  logger.info "event=processing_started podcast_id=#{podcast_id} title=\"#{title}\""

  # Download markdown from GCS
  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
  markdown_content = gcs.download_file(remote_path: staging_path)
  logger.info "event=file_downloaded podcast_id=#{podcast_id} size_bytes=#{markdown_content.bytesize}"

  # Process episode
  processor = EpisodeProcessor.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"), podcast_id)
  processor.process(title, author, description, markdown_content)
  logger.info "event=episode_processed podcast_id=#{podcast_id}"

  # Cleanup staging file
  gcs.delete_file(remote_path: staging_path)
  logger.info "event=staging_cleaned podcast_id=#{podcast_id} staging_path=#{staging_path}"

  logger.info "event=processing_completed podcast_id=#{podcast_id}"
end
```

**Step 6: Update CloudTasksEnqueuer**

Modify `lib/cloud_tasks_enqueuer.rb`:

```ruby
require "google/cloud/tasks"
require "json"

class CloudTasksEnqueuer
  def initialize
    @project_id = ENV.fetch("GOOGLE_CLOUD_PROJECT")
    @location = ENV.fetch("CLOUD_TASKS_LOCATION")
    @queue = ENV.fetch("CLOUD_TASKS_QUEUE")
    @service_url = ENV.fetch("SERVICE_URL")
  end

  # Enqueue episode processing task
  # @param task_payload [Hash] Task data including podcast_id, title, author, description, staging_path
  # @return [String] Task name
  def enqueue_episode_processing(task_payload)
    client = Google::Cloud::Tasks.cloud_tasks

    # Build queue path
    parent = client.queue_path(
      project: @project_id,
      location: @location,
      queue: @queue
    )

    # Build task
    task = {
      http_request: {
        http_method: "POST",
        url: "#{@service_url}/process",
        headers: {
          "Content-Type" => "application/json"
        },
        body: task_payload.to_json,
        oidc_token: {
          service_account_email: "#{@project_id}@appspot.gserviceaccount.com"
        }
      }
    }

    # Create task
    response = client.create_task(parent: parent, task: task)
    response.name
  end
end
```

**Step 7: Run tests**

Run: `ruby test/test_api.rb`
Expected: Tests pass

**Step 8: Run all tests**

Run: `rake test`
Expected: All tests pass

**Step 9: Run RuboCop**

Run: `rake rubocop`
Expected: PASS

**Step 10: Commit**

```bash
git add api.rb lib/publish_params_validator.rb lib/cloud_tasks_enqueuer.rb test/test_api.rb
git commit -m "feat: update API to require and use podcast_id"
```

---

## Task 6: Eliminate temporary MP3 files

**Files:**
- Modify: `lib/episode_processor.rb`
- Modify: `lib/podcast_publisher.rb`

**Step 1: Update GCSUploader to accept StringIO**

Note: `upload_content` already accepts string content, no changes needed.

**Step 2: Update PodcastPublisher to accept audio content**

Modify `lib/podcast_publisher.rb`:

```ruby
require "time"
require "stringio"
require_relative "episode_manifest"
require_relative "rss_generator"

class PodcastPublisher
  # Initialize podcast publisher
  # @param podcast_config [Hash] Podcast-level configuration
  # @param gcs_uploader [GCSUploader] GCS uploader instance
  # @param episode_manifest [EpisodeManifest] Episode manifest instance
  def initialize(podcast_config:, gcs_uploader:, episode_manifest:)
    @podcast_config = podcast_config
    @gcs_uploader = gcs_uploader
    @episode_manifest = episode_manifest
  end

  # Publish episode to podcast feed
  # @param audio_content [String] MP3 audio content (binary string)
  # @param metadata [Hash] Episode metadata (title, description, author)
  # @return [String] Public URL of the RSS feed
  def publish(audio_content, metadata)
    guid = EpisodeManifest.generate_guid(metadata["title"])
    mp3_url = upload_mp3(audio_content, guid)
    episode_data = build_episode_data(metadata, guid, mp3_url, audio_content.bytesize)

    update_manifest(episode_data)
    upload_rss_feed

    @gcs_uploader.get_public_url(remote_path: "feed.xml")
  end

  private

  def upload_mp3(audio_content, guid)
    remote_path = "episodes/#{guid}.mp3"
    @gcs_uploader.upload_content(content: audio_content, remote_path: remote_path)
  end

  def build_episode_data(metadata, guid, mp3_url, file_size)
    {
      "id" => guid,
      "title" => metadata["title"],
      "description" => metadata["description"],
      "author" => metadata["author"],
      "mp3_url" => mp3_url,
      "file_size_bytes" => file_size,
      "published_at" => Time.now.utc.iso8601,
      "guid" => guid
    }
  end

  def update_manifest(episode_data)
    @episode_manifest.load
    @episode_manifest.add_episode(episode_data)
    @episode_manifest.save
  end

  def upload_rss_feed
    feed_url = @gcs_uploader.get_public_url(remote_path: "feed.xml")
    config_with_feed_url = @podcast_config.merge("feed_url" => feed_url)
    rss_generator = RSSGenerator.new(config_with_feed_url, @episode_manifest.episodes)
    rss_xml = rss_generator.generate
    @gcs_uploader.upload_content(content: rss_xml, remote_path: "feed.xml")
  end
end
```

**Step 3: Update EpisodeProcessor to skip temp file**

Modify `lib/episode_processor.rb`:

```ruby
def process(title, author, description, markdown_content)
  print_start(title)
  filename = FilenameGenerator.generate(title)
  episode_id = EpisodeManifest.generate_guid(title)

  # Step 1: Convert markdown to plain text
  text = TextProcessor.convert_to_plain_text(markdown_content)
  puts "✓ Converted to #{text.length} characters of plain text"

  # Step 2: Generate TTS audio
  puts "\n[2/3] Generating TTS audio..."
  tts = TTS.new
  audio_content = tts.synthesize(text)
  audio_duration = estimate_duration(audio_content.bytesize)
  puts "✓ Generated #{format_size(audio_content.bytesize)} of audio"

  # Step 3: Log cost tracking
  CostTracker.log_episode_cost(
    logger: @logger,
    podcast_id: @podcast_id,
    user_id: @user_id,
    episode_id: episode_id,
    tts_characters: text.length,
    audio_duration_seconds: audio_duration,
    audio_size_bytes: audio_content.bytesize
  )

  # Step 4: Publish to podcast feed (no temp file!)
  publish_to_feed(audio_content, title, author, description)

  print_success(title)
end

private

def publish_to_feed(audio_content, title, author, description)
  puts "\n[3/3] Publishing to feed..."

  podcast_config = YAML.safe_load_file("config/podcast.yml")
  gcs_uploader = GCSUploader.new(@bucket_name, podcast_id: @podcast_id)
  episode_manifest = EpisodeManifest.new(gcs_uploader)

  publisher = PodcastPublisher.new(
    podcast_config: podcast_config,
    gcs_uploader: gcs_uploader,
    episode_manifest: episode_manifest
  )

  publisher.publish(audio_content, metadata(title: title, author: author, description: description))

  puts "✓ Published"
end
```

**Step 4: Update generate.rb to keep local file option**

Modify `generate.rb` to save local copy for `--local-only` mode:

```ruby
# Step 4: Save to output directory
puts "\n[#{options[:local_only] ? 3 : 4}/#{options[:local_only] ? 3 : 5}] Saving audio file..."
begin
  # Generate output filename from input filename
  basename = File.basename(input_file, File.extname(input_file))
  output_file = File.join("output", "#{basename}.mp3")

  File.write(output_file, audio_content, mode: "wb")
  puts "✓ Audio saved to: #{output_file}"

  # Show file info
  file_size_kb = (File.size(output_file) / 1024.0).round(1)
  puts "  File size: #{file_size_kb} KB"
rescue StandardError => e
  puts "✗ Error saving file: #{e.message}"
  exit 1
end

# Step 5: Publish to podcast feed (unless --local-only)
unless options[:local_only]
  puts "\n[5/5] Publishing to podcast feed..."
  begin
    # Load podcast config
    podcast_config = YAML.safe_load_file("config/podcast.yml")

    # Initialize GCS and manifest
    podcast_id = ENV.fetch("PODCAST_ID", nil)
    gcs_uploader = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    # Publish episode
    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    # Convert symbol keys to string keys for publisher
    metadata_with_string_keys = metadata.transform_keys(&:to_s)
    feed_url = publisher.publish(audio_content, metadata_with_string_keys)

    puts "✓ Episode published successfully"
    puts "  Feed URL: #{feed_url}"
    puts "  Episodes in feed: #{episode_manifest.episodes.length}"
  rescue StandardError => e
    puts "✗ Error publishing episode: #{e.message}"
    puts "  Local MP3 file saved successfully at: #{output_file}"
    exit 1
  end
end
```

**Step 5: Run all tests**

Run: `rake test`
Expected: All tests pass (may need to update test mocks)

**Step 6: Run RuboCop**

Run: `rake rubocop`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/podcast_publisher.rb lib/episode_processor.rb generate.rb
git commit -m "feat: eliminate temporary MP3 files, stream directly to GCS"
```

---

## Task 7: Update documentation

**Files:**
- Modify: `README.md`
- Create: `docs/wave-2-migration.md`

**Step 1: Update README.md**

Add section about Wave 2 changes:

```markdown
## Wave 2: Podcast Isolation

Starting with Wave 2, all podcast data is isolated by `podcast_id`:

### Storage Structure
```
podcasts/{podcast_id}/
  ├── episodes/{episode_id}.mp3
  ├── feed.xml
  ├── manifest.json
  └── staging/{filename}.md
```

### Local Usage

Add to your `.env`:
```bash
PODCAST_ID=podcast_your_unique_id
```

Then use `generate.rb` as before:
```bash
ruby generate.rb input/article.md
```

### API Usage (Service-to-Service)

The API now requires `podcast_id` and uses IAM authentication:

```bash
# Get identity token (from authorized service)
TOKEN=$(gcloud auth print-identity-token)

curl -X POST https://podcast-api-ns2hvyzzra-wm.a.run.app/publish \
  -H "Authorization: Bearer $TOKEN" \
  -F "podcast_id=podcast_abc123" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@input/article.md"
```

### Feed URLs

Each podcast has its own feed URL:
```
https://storage.googleapis.com/{bucket}/podcasts/{podcast_id}/feed.xml
```
```

**Step 2: Create migration guide**

Create `docs/wave-2-migration.md`:

```markdown
# Wave 2 Migration Guide

This guide helps you migrate from Wave 1 (flat storage) to Wave 2 (podcast-scoped storage).

## Breaking Changes

1. **Storage structure**: Files moved from flat structure to `podcasts/{podcast_id}/`
2. **API changes**: `/publish` endpoint now requires `podcast_id` parameter
3. **Authentication**: API now uses IAM tokens instead of `API_SECRET_TOKEN`
4. **Local usage**: `generate.rb` requires `PODCAST_ID` environment variable

## Migration Steps

### 1. Set up Firestore

Enable Firestore in your GCP project:
```bash
gcloud firestore databases create --region=us-west3
```

### 2. Add PODCAST_ID to .env

Generate a unique podcast ID:
```bash
echo "PODCAST_ID=podcast_$(openssl rand -hex 6)" >> .env
```

### 3. Migrate existing episodes (optional)

If you have existing episodes in flat structure, migrate them:

```bash
# Example migration script (customize for your bucket)
PODCAST_ID="your_podcast_id"
BUCKET="your_bucket"

# Move episodes
gsutil -m mv "gs://$BUCKET/episodes/*" "gs://$BUCKET/podcasts/$PODCAST_ID/episodes/"

# Move feed and manifest
gsutil mv "gs://$BUCKET/feed.xml" "gs://$BUCKET/podcasts/$PODCAST_ID/"
gsutil mv "gs://$BUCKET/manifest.json" "gs://$BUCKET/podcasts/$PODCAST_ID/"
```

### 4. Update API callers

If calling the API, update requests to include `podcast_id` and use IAM tokens.

### 5. Deploy updated service

```bash
./bin/deploy
```

## Rollback Plan

If you need to rollback:

1. Restore Wave 1 code from git
2. Move files back to flat structure
3. Re-deploy

Old feed URLs will continue working if you don't delete the flat files.
```

**Step 3: Commit documentation**

```bash
git add README.md docs/wave-2-migration.md
git commit -m "docs: update for Wave 2 podcast isolation"
```

---

## Task 8: Migrate existing episodes to podcast-scoped structure

**Files:**
- None (GCS operations only)

**Step 1: Choose your podcast ID**

Generate a unique podcast ID:
```bash
echo "podcast_$(openssl rand -hex 6)"
```

Save this value - you'll use it in `.env` as `PODCAST_ID`.

Example: `podcast_a1b2c3d4e5f6`

**Step 2: Set PODCAST_ID in .env**

Add to `.env`:
```bash
PODCAST_ID=podcast_a1b2c3d4e5f6  # Use your generated ID
```

**Step 3: Check what exists in current bucket**

Run: `gsutil ls -r gs://YOUR_BUCKET/ | head -30`
Expected: See existing `episodes/`, `feed.xml`, `manifest.json`

**Step 4: Create podcast directory structure**

Run: `gsutil ls gs://YOUR_BUCKET/podcasts/$PODCAST_ID/ || echo "Will be created during migration"`
Expected: Directory doesn't exist yet (that's fine)

**Step 5: Migrate episodes**

Run:
```bash
PODCAST_ID="YOUR_PODCAST_ID"  # Replace with your actual ID
BUCKET="YOUR_BUCKET"          # Replace with your bucket name

# Move episodes (if any exist)
gsutil -m mv "gs://$BUCKET/episodes/*" "gs://$BUCKET/podcasts/$PODCAST_ID/episodes/" 2>/dev/null || echo "No episodes to migrate"

# Move feed.xml
gsutil mv "gs://$BUCKET/feed.xml" "gs://$BUCKET/podcasts/$PODCAST_ID/feed.xml" 2>/dev/null || echo "No feed.xml to migrate"

# Move manifest.json
gsutil mv "gs://$BUCKET/manifest.json" "gs://$BUCKET/podcasts/$PODCAST_ID/manifest.json" 2>/dev/null || echo "No manifest.json to migrate"
```

**Step 6: Verify migration**

Run: `gsutil ls -r gs://$BUCKET/podcasts/$PODCAST_ID/`
Expected: See episodes/, feed.xml, manifest.json in new location

**Step 7: Verify old location is empty**

Run: `gsutil ls gs://$BUCKET/episodes/ 2>&1`
Expected: "CommandException: One or more URLs matched no objects" (old location is empty)

**Step 8: Test new feed URL**

Run: `curl https://storage.googleapis.com/$BUCKET/podcasts/$PODCAST_ID/feed.xml | head -20`
Expected: Valid RSS XML with your episodes

**Step 9: Update podcast app subscription**

1. Open your podcast app
2. Remove old feed: `https://storage.googleapis.com/$BUCKET/feed.xml`
3. Add new feed: `https://storage.googleapis.com/$BUCKET/podcasts/$PODCAST_ID/feed.xml`
4. Verify episodes appear correctly

**Step 10: Document your podcast URL**

Save for reference:
```bash
echo "My podcast feed: https://storage.googleapis.com/$BUCKET/podcasts/$PODCAST_ID/feed.xml" >> .podcast-url
git add .podcast-url
git commit -m "docs: save podcast feed URL for reference"
```

---

## Task 9: Test end-to-end locally

**Step 1: Set environment variables**

Ensure `.env` has:
```bash
GOOGLE_CLOUD_PROJECT=your-project
GOOGLE_CLOUD_BUCKET=your-bucket
GOOGLE_APPLICATION_CREDENTIALS=./credentials.json
PODCAST_ID=podcast_test_wave2
```

**Step 2: Run generate.rb**

Run: `ruby generate.rb input/sample.md`
Expected: Episode published to `podcasts/podcast_test_wave2/`

**Step 3: Verify GCS structure**

Run: `gsutil ls -r gs://YOUR_BUCKET/podcasts/podcast_test_wave2/`
Expected: See episodes/, feed.xml, manifest.json

**Step 4: Check logs for cost tracking**

Look for JSON log output with `event: "episode_cost"`

**Step 5: Test feed URL**

Run: `curl https://storage.googleapis.com/YOUR_BUCKET/podcasts/podcast_test_wave2/feed.xml`
Expected: Valid RSS XML with episode

**Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass

Run: `rake rubocop`
Expected: No offenses

**Step 7: Create final commit**

```bash
git add .
git commit -m "test: verify Wave 2 end-to-end functionality"
```

---

## Completion Checklist

- [ ] All tests pass (`rake test`)
- [ ] RuboCop passes (`rake rubocop`)
- [ ] Local `generate.rb` works with `PODCAST_ID`
- [ ] GCS storage uses `podcasts/{podcast_id}/` structure
- [ ] Cost tracking logs output structured JSON
- [ ] API accepts `podcast_id` parameter
- [ ] IAM authentication configured
- [ ] Temporary MP3 files eliminated
- [ ] Documentation updated
- [ ] All commits follow conventional commit format

---

## Next Steps (Wave 3)

After Wave 2 is complete and tested:

1. Build Web UI service with user authentication
2. Implement Firestore user → podcast mapping
3. Add episode management APIs (delete, edit, reorder)
4. Add Firestore cost aggregates for real-time dashboards
5. Consider collaboration features (multi-user podcasts)
