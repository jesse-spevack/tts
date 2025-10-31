# Implementation Plan: Podcast Publishing API

## Overview

This plan details how to build a minimal HTTP API that accepts podcast episode submissions via cURL and publishes them to the podcast feed. The system uses two Google Cloud Run services connected by Google Cloud Tasks for serverless asynchronous processing.

### What We're Building

Two Cloud Run services:

**Service 1: API Service** - Fast, accepts requests:
1. Accepts authentication via Bearer token
2. Receives episode metadata (title, author, description) and markdown content file
3. Validates input
4. Uploads content to GCS staging area
5. Enqueues job to Google Cloud Tasks
6. Returns immediate success/error response

**Service 2: Worker Service** - Heavy lifting:
1. Triggered by Cloud Tasks
2. Downloads markdown from GCS staging
3. Processes markdown to plain text
4. Generates TTS audio
5. Uploads audio to GCS
6. Publishes to podcast feed
7. Cleans up staging files
8. Logs results to Google Cloud Logging

### User Flow

```bash
curl -X POST https://your-podcast-api.run.app/publish \
  -H "Authorization: Bearer secret123" \
  -F "title=The Programmer Identity Crisis" \
  -F "author=Unknown" \
  -F "description=A reflection on AI and programming" \
  -F "content=@article.md"

# Response (immediate):
{"status":"success","message":"Episode submitted for processing"}
```

### Architecture

```
┌─────────────┐
│   Client    │
│   (cURL)    │
└──────┬──────┘
       │ POST /publish
       │ multipart/form-data
       ▼
┌─────────────────────────┐
│  API Service            │
│  (Cloud Run)            │
├─────────────────────────┤
│ 1. Auth Check           │
│ 2. Validate Input       │
│ 3. Upload to GCS        │
│ 4. Create Cloud Task    │
│ 5. Return Success       │
└──────┬──────────────────┘
       │ Cloud Tasks Queue
       │ (Managed Service)
       ▼
┌─────────────────────────┐
│  Worker Service         │
│  (Cloud Run)            │
├─────────────────────────┤
│ 1. Download from GCS    │
│ 2. Process Markdown     │
│ 3. Generate TTS         │
│ 4. Upload Audio         │
│ 5. Update RSS Feed      │
│ 6. Cleanup Staging      │
│ 7. Log Results          │
└─────────────────────────┘
```

## Prerequisites

### Knowledge Requirements

**Ruby & Sinatra**: Basic understanding of Ruby syntax and Sinatra web framework
- Tutorial: https://sinatrarb.com/intro.html
- Focus on: routes, params, request/response objects

**Testing with Minitest**: Read existing tests in `test/` to understand patterns
- Key file: `test/CLAUDE.md` - Contains project-specific testing guidelines
- Pattern: Write tests first (TDD), focus on business logic, avoid testing Ruby stdlib

**Google Cloud Run**: Understanding of containerized deployments
- Tutorial: https://cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-ruby-service
- Key concepts: Docker containers, environment variables, Cloud Logging

**Google Cloud Tasks**: Understanding of task queues
- Tutorial: https://cloud.google.com/tasks/docs/creating-http-target-tasks
- Key concepts: Task queues, HTTP targets, automatic retries

### Tools Setup

1. **Install Docker Desktop**: https://www.docker.com/products/docker-desktop/
   - Required for local testing and Cloud Run deployment
   - Verify: `docker --version`

2. **Install Google Cloud SDK**: https://cloud.google.com/sdk/docs/install
   - Required for Cloud Run and Cloud Tasks deployment
   - Verify: `gcloud --version`

3. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   gcloud auth configure-docker
   ```

4. **Enable required APIs**:
   ```bash
   gcloud services enable run.googleapis.com
   gcloud services enable cloudtasks.googleapis.com
   ```

## Task Breakdown

### Phase 1: Dependencies

#### Task 1.1: Add Required Gems

**What**: Add Google Cloud Tasks and Sinatra gems for the API and worker services.

**Why**: We need Cloud Tasks to communicate between services asynchronously, and Sinatra to build the web APIs.

**Files to modify**:
- `Gemfile`

**What to do**:

1. Add gems to `Gemfile`:
   ```ruby
   # Add after google-cloud-storage
   gem "google-cloud-tasks", "~> 2.0"

   # Web framework
   gem "sinatra"
   gem "sinatra-contrib" # Adds useful helpers like json
   gem "puma"            # Production web server
   gem "rack-test", group: :test  # For testing Sinatra apps
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Verify installation:
   ```bash
   bundle list | grep -E "(google-cloud-tasks|sinatra|puma)"
   ```

**Testing**: No tests needed - just dependency installation.

**Commit**:
```bash
git add Gemfile Gemfile.lock
git commit -m "Add Cloud Tasks and Sinatra dependencies"
```

---

### Phase 2: Shared Utilities

#### Task 2.1: Create FilenameGenerator Module (Test First)

**What**: Create a shared module for generating filenames from titles.

**Why**: Both the API and Worker need to generate consistent filenames from episode titles. Extracting this to a module follows DRY principles.

**Files to create**:
- `test/test_filename_generator.rb` (create FIRST)
- `lib/filename_generator.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_filename_generator.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/filename_generator"

class TestFilenameGenerator < Minitest::Test
  def test_generates_filename_with_date_and_slug
    filename = FilenameGenerator.generate("My Test Title")
    assert_match(/^\d{4}-\d{2}-\d{2}-my-test-title$/, filename)
  end

  def test_removes_special_characters
    filename = FilenameGenerator.generate("Title with (special) chars!")
    assert_match(/title-with-special-chars$/, filename)
  end

  def test_converts_spaces_to_hyphens
    filename = FilenameGenerator.generate("Title With Spaces")
    assert_match(/title-with-spaces$/, filename)
  end

  def test_collapses_multiple_hyphens
    filename = FilenameGenerator.generate("Title   with   spaces")
    refute_match(/--/, filename)
  end

  def test_handles_unicode_characters
    filename = FilenameGenerator.generate("Café résumé")
    assert_match(/caf-rsum$/, filename)
  end

  def test_strips_leading_and_trailing_whitespace
    filename = FilenameGenerator.generate("  Title  ")
    assert_match(/title$/, filename)
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_filename_generator.rb
# Expected: LoadError - cannot load such file
```

**Step 3: Create implementation**

Create `lib/filename_generator.rb`:

```ruby
require "time"

# Generates consistent filenames from episode titles
# Format: YYYY-MM-DD-slugified-title
module FilenameGenerator
  # Generate a filename from a title
  # @param title [String] Episode title
  # @return [String] Filename in format YYYY-MM-DD-slug
  def self.generate(title)
    date = Time.now.strftime("%Y-%m-%d")
    slug = slugify(title)
    "#{date}-#{slug}"
  end

  # Convert title to URL-safe slug
  # @param title [String] Title to slugify
  # @return [String] Slugified title
  def self.slugify(title)
    title.downcase
         .gsub(/[^\w\s-]/, "") # Remove special chars
         .gsub(/\s+/, "-")      # Spaces to hyphens
         .gsub(/-+/, "-")       # Collapse multiple hyphens
         .strip                 # Remove leading/trailing whitespace
  end
end
```

**Step 4: Run tests**

```bash
ruby test/test_filename_generator.rb
# Should pass
```

**Step 5: Run all tests**

```bash
rake test
```

**Step 6: Check code style**

```bash
rake rubocop
# Fix any issues
```

**Commit**:
```bash
git add lib/filename_generator.rb test/test_filename_generator.rb
git commit -m "Add FilenameGenerator module for consistent file naming"
```

---

### Phase 3: API Service

#### Task 3.1: Create API Service (Test First)

**What**: Create the API Sinatra application with the `/publish` endpoint.

**Why**: This is the public-facing service that accepts episode submissions and enqueues them for processing.

**Files to create**:
- `test/test_api.rb` (create FIRST)
- `api.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_api.rb`:

```ruby
require "minitest/autorun"
require "rack/test"
require "json"
require_relative "../api"

class TestAPI < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    ENV["API_SECRET_TOKEN"] = "test-token-123"
    ENV["GOOGLE_CLOUD_PROJECT"] = "test-project"
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
    ENV["WORKER_URL"] = "https://test-worker.run.app/process"
    ENV["CLOUD_TASKS_LOCATION"] = "us-central1"
    ENV["CLOUD_TASKS_QUEUE"] = "episode-processing"
  end

  # Health Check Tests

  def test_health_check_returns_200
    get "/health"
    assert_equal 200, last_response.status
  end

  def test_health_check_validates_environment
    get "/health"
    body = JSON.parse(last_response.body)

    assert_equal "healthy", body["status"]
    assert body["checks"]["env_vars_set"]
  end

  # Authentication Tests

  def test_missing_auth_header_returns_401
    post "/publish"
    assert_equal 401, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
    assert_includes body["message"].downcase, "unauthorized"
  end

  def test_invalid_auth_token_returns_401
    post "/publish", {}, { "HTTP_AUTHORIZATION" => "Bearer wrong-token" }
    assert_equal 401, last_response.status
  end

  def test_valid_auth_token_with_missing_data_returns_400_not_401
    post "/publish", {}, auth_header
    assert_equal 400, last_response.status # Not 401
  end

  # Validation Tests

  def test_missing_title_returns_400
    post "/publish", params_without(:title), auth_header
    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
    assert_includes body["message"], "title"
  end

  def test_missing_author_returns_400
    post "/publish", params_without(:author), auth_header
    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_includes body["message"], "author"
  end

  def test_missing_description_returns_400
    post "/publish", params_without(:description), auth_header
    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_includes body["message"], "description"
  end

  def test_missing_content_file_returns_400
    post "/publish", params_without(:content), auth_header
    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_includes body["message"], "content"
  end

  def test_empty_content_file_returns_400
    post "/publish", valid_params.merge(content: empty_file), auth_header
    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_includes body["message"], "content"
  end

  private

  def auth_header
    { "HTTP_AUTHORIZATION" => "Bearer test-token-123" }
  end

  def valid_params
    {
      title: "Test Title",
      author: "Test Author",
      description: "Test Description",
      content: markdown_file
    }
  end

  def params_without(key)
    valid_params.reject { |k, _| k == key }
  end

  def markdown_file
    Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content\n\nThis is a test article."),
      "text/markdown",
      original_filename: "test.md"
    )
  end

  def empty_file
    Rack::Test::UploadedFile.new(
      StringIO.new(""),
      "text/markdown",
      original_filename: "empty.md"
    )
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_api.rb
# Expected: LoadError - cannot load api.rb
```

**Step 3: Create the Sinatra app**

Create `api.rb`:

```ruby
require "sinatra"
require "sinatra/json"
require "google/cloud/tasks/v2"
require_relative "lib/gcs_uploader"
require_relative "lib/filename_generator"

# Configure Sinatra
set :port, ENV.fetch("PORT", 8080)
set :bind, "0.0.0.0"
set :show_exceptions, false

# Health check endpoint with environment validation
get "/health" do
  required_vars = %w[
    GOOGLE_CLOUD_PROJECT
    GOOGLE_CLOUD_BUCKET
    API_SECRET_TOKEN
    WORKER_URL
    CLOUD_TASKS_LOCATION
    CLOUD_TASKS_QUEUE
  ]

  missing_vars = required_vars.reject { |var| ENV[var] }

  if missing_vars.empty?
    json status: "healthy", checks: { env_vars_set: true }
  else
    halt 500, json(
      status: "unhealthy",
      checks: { env_vars_set: false },
      missing_vars: missing_vars
    )
  end
end

# Episode publishing endpoint
post "/publish" do
  # Step 1: Authenticate
  unless authenticated?
    halt 401, json(status: "error", message: "Unauthorized: Invalid or missing authentication token")
  end

  # Step 2: Validate required fields
  validation_error = validate_params
  if validation_error
    halt 400, json(status: "error", message: validation_error)
  end

  # Step 3: Extract parameters
  title = params[:title]
  author = params[:author]
  description = params[:description]
  content_file = params[:content]

  # Step 4: Read file content
  markdown_content = content_file[:tempfile].read

  # Step 5: Upload to GCS staging area
  staging_path = upload_to_staging(title, markdown_content)
  logger.info "Uploaded to GCS: #{staging_path}"

  # Step 6: Enqueue Cloud Task
  enqueue_processing_task(title, author, description, staging_path)
  logger.info "Enqueued task for: #{title}"

  # Step 7: Return success
  json status: "success", message: "Episode submitted for processing"
rescue StandardError => e
  logger.error "Error processing request: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end

# Authentication helper
def authenticated?
  auth_header = request.env["HTTP_AUTHORIZATION"]
  return false unless auth_header

  token = auth_header.split(" ").last
  expected_token = ENV.fetch("API_SECRET_TOKEN", nil)

  return false unless expected_token

  token == expected_token
end

# Validation helper
def validate_params
  return "Missing required field: title" if params[:title].nil? || params[:title].empty?
  return "Missing required field: author" if params[:author].nil? || params[:author].empty?
  return "Missing required field: description" if params[:description].nil? || params[:description].empty?
  return "Missing required field: content" if params[:content].nil?

  content_file = params[:content]

  # Check if file was uploaded
  return "Missing required field: content" unless content_file.is_a?(Hash) && content_file[:tempfile]

  # Check if file is empty
  content = content_file[:tempfile].read
  content_file[:tempfile].rewind # Reset for later reading

  return "Content file is empty" if content.strip.empty?

  nil # No errors
end

# Upload markdown to GCS staging area
def upload_to_staging(title, content)
  filename = FilenameGenerator.generate(title)
  staging_path = "staging/#{filename}.md"

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
  gcs.upload_content(content: content, remote_path: staging_path)

  staging_path
end

# Enqueue task to Cloud Tasks (inlined - no abstraction)
def enqueue_processing_task(title, author, description, gcs_path)
  client = Google::Cloud::Tasks::V2::CloudTasks::Client.new

  project_id = ENV.fetch("GOOGLE_CLOUD_PROJECT")
  location = ENV.fetch("CLOUD_TASKS_LOCATION")
  queue_name = ENV.fetch("CLOUD_TASKS_QUEUE")
  worker_url = ENV.fetch("WORKER_URL")

  queue_path = client.queue_path(
    project: project_id,
    location: location,
    queue: queue_name
  )

  payload = {
    title: title,
    author: author,
    description: description,
    gcs_path: gcs_path
  }

  task = {
    http_request: {
      http_method: "POST",
      url: worker_url,
      headers: {
        "Content-Type" => "application/json"
      },
      body: payload.to_json
    }
  }

  client.create_task(parent: queue_path, task: task)
end
```

**Step 4: Run tests**

```bash
ruby test/test_api.rb
# Should pass (tests don't hit real GCS/Cloud Tasks)
```

**Step 5: Run all tests**

```bash
rake test
rake rubocop
```

**Commit**:
```bash
git add api.rb test/test_api.rb
git commit -m "Add API service with /publish endpoint and health checks"
```

---

#### Task 3.2: Create API Dockerfile

**What**: Create a Dockerfile for the API service.

**Why**: Cloud Run requires a container image to deploy.

**Files to create**:
- `Dockerfile.api`
- `.dockerignore` (if doesn't exist)

**What to do**:

Create `Dockerfile.api`:
```dockerfile
# Use official Ruby image
FROM ruby:3.4.5-slim

# Install dependencies
RUN apt-get update -qq && \
    apt-get install -y build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development' && \
    bundle install

# Copy application code
COPY lib/ ./lib/
COPY config/ ./config/
COPY api.rb ./

# Expose port
EXPOSE 8080

# Start application
CMD ["bundle", "exec", "ruby", "api.rb"]
```

Create `.dockerignore` (if doesn't exist):
```
.git
.env
.DS_Store
*.md
docs/
test/
output/*.mp3
input/*.md
.rubocop.yml
Rakefile
generate.rb
test_single_chunk.rb
.ruby-lsp/
very-normal-text-to-speech-*.json
worker.rb
Dockerfile.worker
```

**Testing**:

```bash
docker build -f Dockerfile.api -t podcast-api .
```

**Commit**:
```bash
git add Dockerfile.api .dockerignore
git commit -m "Add Dockerfile for API service"
```

---

### Phase 4: Worker Service Components

#### Task 4.1: Create FileManager Class (Test First)

**What**: Create a class to handle file operations (upload, download, delete from GCS).

**Why**: Separates file management concerns from business logic, making the code more testable and maintainable.

**Files to create**:
- `test/test_file_manager.rb` (create FIRST)
- `lib/file_manager.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_file_manager.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/file_manager"

class TestFileManager < Minitest::Test
  def test_save_mp3_creates_output_directory
    manager = FileManager.new("test-bucket")

    # Mock directory creation
    Dir.stub :exist?, false do
      Dir.stub :mkdir, nil do
        path = manager.save_mp3_locally("test-file", "audio-content")
        assert_equal "output/test-file.mp3", path
      end
    end
  end

  def test_builds_staging_path
    manager = FileManager.new("test-bucket")
    path = manager.staging_path("my-file")
    assert_equal "staging/my-file.md", path
  end

  def test_builds_input_archive_path
    manager = FileManager.new("test-bucket")
    path = manager.input_archive_path("my-file")
    assert_equal "input/my-file.md", path
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_file_manager.rb
# Expected: LoadError
```

**Step 3: Create implementation**

Create `lib/file_manager.rb`:

```ruby
require_relative "gcs_uploader"

# Manages file operations for episode processing
# Handles local MP3 storage and GCS file lifecycle
class FileManager
  attr_reader :bucket_name

  def initialize(bucket_name)
    @bucket_name = bucket_name
    @gcs = GCSUploader.new(bucket_name)
  end

  # Download markdown from GCS staging
  # @param staging_path [String] Path in GCS (e.g., "staging/file.md")
  # @return [String] File contents
  def download_from_staging(staging_path)
    @gcs.download_file(remote_path: staging_path)
  end

  # Save markdown to GCS with frontmatter for archival
  # @param filename [String] Base filename without extension
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param content [String] Markdown content
  def save_markdown_to_archive(filename, title, author, description, content)
    frontmatter = build_frontmatter(title, author, description)
    full_content = frontmatter + content

    path = input_archive_path(filename)
    @gcs.upload_content(content: full_content, remote_path: path)

    path
  end

  # Save MP3 to local output directory (temporary)
  # @param filename [String] Base filename without extension
  # @param audio_content [String] Binary audio data
  # @return [String] Local file path
  def save_mp3_locally(filename, audio_content)
    Dir.mkdir("output") unless Dir.exist?("output")
    path = File.join("output", "#{filename}.mp3")
    File.write(path, audio_content, mode: "wb")
    path
  end

  # Delete MP3 from local filesystem
  # @param local_path [String] Path to local file
  def delete_local_mp3(local_path)
    File.delete(local_path) if File.exist?(local_path)
  end

  # Delete staging file from GCS
  # @param staging_path [String] Path in GCS staging area
  def cleanup_staging(staging_path)
    @gcs.delete_file(remote_path: staging_path)
  end

  # Get staging path for a filename
  # @param filename [String] Base filename
  # @return [String] GCS staging path
  def staging_path(filename)
    "staging/#{filename}.md"
  end

  # Get input archive path for a filename
  # @param filename [String] Base filename
  # @return [String] GCS input path
  def input_archive_path(filename)
    "input/#{filename}.md"
  end

  private

  def build_frontmatter(title, author, description)
    "---\ntitle: \"#{title}\"\nauthor: \"#{author}\"\ndescription: \"#{description}\"\n---\n\n"
  end
end
```

**Step 4: Add download_file and delete_file to GCSUploader**

Edit `lib/gcs_uploader.rb` and add these methods:

```ruby
# Download a file from GCS
# @param remote_path [String] Path in bucket (e.g., "staging/file.md")
# @return [String] File contents
def download_file(remote_path:)
  file = @bucket.file(remote_path)
  raise "File not found: #{remote_path}" unless file

  file.download.read
end

# Delete a file from GCS
# @param remote_path [String] Path in bucket (e.g., "staging/file.md")
def delete_file(remote_path:)
  file = @bucket.file(remote_path)
  file.delete if file
end
```

**Step 5: Run tests**

```bash
ruby test/test_file_manager.rb
rake test
rake rubocop
```

**Commit**:
```bash
git add lib/file_manager.rb lib/gcs_uploader.rb test/test_file_manager.rb
git commit -m "Add FileManager for GCS and local file operations"
```

---

#### Task 4.2: Create AudioGenerator Class (Test First)

**What**: Create a class to handle TTS audio generation.

**Why**: Separates audio generation logic from the orchestration, making it easier to test and potentially swap TTS providers later.

**Files to create**:
- `test/test_audio_generator.rb` (create FIRST)
- `lib/audio_generator.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_audio_generator.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/audio_generator"

class TestAudioGenerator < Minitest::Test
  def test_initialization_with_default_voice
    generator = AudioGenerator.new
    assert_equal "en-GB-Chirp3-HD-Enceladus", generator.voice
  end

  def test_initialization_with_custom_voice
    generator = AudioGenerator.new(voice: "en-US-Chirp3-HD-Galahad")
    assert_equal "en-US-Chirp3-HD-Galahad", generator.voice
  end

  def test_calculates_audio_size_in_kb
    generator = AudioGenerator.new
    size_kb = generator.send(:format_size, 1024)
    assert_equal "1.0 KB", size_kb
  end

  def test_calculates_audio_size_in_mb
    generator = AudioGenerator.new
    size_mb = generator.send(:format_size, 1_048_576)
    assert_equal "1.0 MB", size_mb
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_audio_generator.rb
```

**Step 3: Create implementation**

Create `lib/audio_generator.rb`:

```ruby
require_relative "tts"

# Generates audio from text using TTS
# Wraps the TTS class with logging and formatting
class AudioGenerator
  attr_reader :voice

  def initialize(voice: nil)
    @voice = voice || ENV.fetch("TTS_VOICE", "en-GB-Chirp3-HD-Enceladus")
    @tts = TTS.new
  end

  # Generate audio from text
  # @param text [String] Plain text to convert to speech
  # @return [String] Binary audio content (MP3)
  def generate(text)
    puts "Generating audio with voice: #{@voice}"
    puts "Text length: #{text.length} characters"

    audio_content = @tts.synthesize(text, voice: @voice)

    puts "Generated audio: #{format_size(audio_content.bytesize)}"

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

**Step 4: Run tests**

```bash
ruby test/test_audio_generator.rb
rake test
rake rubocop
```

**Commit**:
```bash
git add lib/audio_generator.rb test/test_audio_generator.rb
git commit -m "Add AudioGenerator for TTS audio generation"
```

---

#### Task 4.3: Create FeedPublisher Class (Test First)

**What**: Create a class to handle podcast feed publishing.

**Why**: Separates RSS feed and episode manifest logic from the orchestration.

**Files to create**:
- `test/test_feed_publisher.rb` (create FIRST)
- `lib/feed_publisher.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_feed_publisher.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/feed_publisher"

class TestFeedPublisher < Minitest::Test
  def test_builds_episode_metadata
    publisher = FeedPublisher.new("test-bucket")

    metadata = publisher.send(
      :build_metadata,
      "Test Title",
      "Test Author",
      "Test Description"
    )

    assert_equal "Test Title", metadata["title"]
    assert_equal "Test Author", metadata["author"]
    assert_equal "Test Description", metadata["description"]
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_feed_publisher.rb
```

**Step 3: Create implementation**

Create `lib/feed_publisher.rb`:

```ruby
require "yaml"
require_relative "gcs_uploader"
require_relative "podcast_publisher"
require_relative "episode_manifest"

# Publishes episodes to the podcast feed
# Orchestrates uploading MP3, updating manifest, and regenerating RSS
class FeedPublisher
  def initialize(bucket_name)
    @bucket_name = bucket_name
    @gcs_uploader = GCSUploader.new(bucket_name)
    @episode_manifest = EpisodeManifest.new(@gcs_uploader)
  end

  # Publish episode to podcast feed
  # @param mp3_path [String] Path to local MP3 file
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @return [String] URL of the published RSS feed
  def publish(mp3_path, title, author, description)
    puts "Publishing episode to podcast feed..."

    podcast_config = load_podcast_config
    metadata = build_metadata(title, author, description)

    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: @gcs_uploader,
      episode_manifest: @episode_manifest
    )

    feed_url = publisher.publish(mp3_path, metadata)

    puts "Episode published to feed: #{feed_url}"

    feed_url
  end

  private

  def load_podcast_config
    YAML.load_file("config/podcast.yml")
  end

  def build_metadata(title, author, description)
    {
      "title" => title,
      "author" => author,
      "description" => description
    }
  end
end
```

**Step 4: Run tests**

```bash
ruby test/test_feed_publisher.rb
rake test
rake rubocop
```

**Commit**:
```bash
git add lib/feed_publisher.rb test/test_feed_publisher.rb
git commit -m "Add FeedPublisher for podcast RSS publishing"
```

---

#### Task 4.4: Create EpisodeProcessor Orchestrator (Test First)

**What**: Create the main orchestrator that coordinates FileManager, AudioGenerator, and FeedPublisher.

**Why**: This is the "controller" that executes the full episode processing workflow.

**Files to create**:
- `test/test_episode_processor.rb` (create FIRST)
- `lib/episode_processor.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_episode_processor.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/episode_processor"

class TestEpisodeProcessor < Minitest::Test
  def test_initialization_with_bucket
    processor = EpisodeProcessor.new("test-bucket")
    assert_equal "test-bucket", processor.bucket_name
  end

  def test_initialization_uses_env_bucket
    ENV["GOOGLE_CLOUD_BUCKET"] = "env-bucket"
    processor = EpisodeProcessor.new
    assert_equal "env-bucket", processor.bucket_name
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_episode_processor.rb
```

**Step 3: Create implementation**

Create `lib/episode_processor.rb`:

```ruby
require_relative "text_processor"
require_relative "file_manager"
require_relative "audio_generator"
require_relative "feed_publisher"
require_relative "filename_generator"

# Orchestrates episode processing from markdown to published podcast
# Coordinates FileManager, AudioGenerator, and FeedPublisher
class EpisodeProcessor
  attr_reader :bucket_name

  def initialize(bucket_name = nil)
    @bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET")
    @file_manager = FileManager.new(@bucket_name)
    @audio_generator = AudioGenerator.new
    @feed_publisher = FeedPublisher.new(@bucket_name)
  end

  # Process an episode from start to finish
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def process(title, author, description, markdown_content)
    puts "=" * 60
    puts "Starting episode processing: #{title}"
    puts "=" * 60

    filename = FilenameGenerator.generate(title)
    mp3_path = nil

    begin
      # Step 1: Process markdown to plain text
      puts "\n[1/5] Processing markdown..."
      text = TextProcessor.convert_to_plain_text(markdown_content)
      puts "✓ Processed #{text.length} characters"

      # Step 2: Generate TTS audio
      puts "\n[2/5] Generating audio..."
      audio_content = @audio_generator.generate(text)
      puts "✓ Audio generated"

      # Step 3: Save MP3 locally (temporary)
      puts "\n[3/5] Saving audio file..."
      mp3_path = @file_manager.save_mp3_locally(filename, audio_content)
      puts "✓ Saved to: #{mp3_path}"

      # Step 4: Publish to podcast feed
      puts "\n[4/5] Publishing to podcast feed..."
      @feed_publisher.publish(mp3_path, title, author, description)
      puts "✓ Published to feed"

      # Step 5: Archive markdown to GCS
      puts "\n[5/5] Archiving markdown..."
      archive_path = @file_manager.save_markdown_to_archive(
        filename, title, author, description, markdown_content
      )
      puts "✓ Archived to: #{archive_path}"

      puts "\n" + "=" * 60
      puts "✓ Episode published successfully!"
      puts "=" * 60
    ensure
      # Always cleanup local MP3 file
      if mp3_path
        @file_manager.delete_local_mp3(mp3_path)
        puts "✓ Cleaned up local file: #{mp3_path}"
      end
    end
  end

  # Cleanup staging file from GCS
  # @param staging_path [String] Path to staging file
  def cleanup_staging(staging_path)
    @file_manager.cleanup_staging(staging_path)
    puts "✓ Cleaned up staging: #{staging_path}"
  rescue StandardError => e
    puts "⚠ Warning: Failed to cleanup staging file: #{e.message}"
    # Don't fail the whole process if cleanup fails
  end
end
```

**Step 4: Run tests**

```bash
ruby test/test_episode_processor.rb
rake test
rake rubocop
```

**Commit**:
```bash
git add lib/episode_processor.rb test/test_episode_processor.rb
git commit -m "Add EpisodeProcessor orchestrator for episode workflow"
```

---

#### Task 4.5: Create Worker Service (Test First)

**What**: Create the Worker Sinatra application that processes episodes.

**Why**: This service is triggered by Cloud Tasks to do the heavy TTS processing.

**Files to create**:
- `test/test_worker.rb` (create FIRST)
- `worker.rb` (create AFTER tests)

**What to do**:

**Step 1: Write tests first**

Create `test/test_worker.rb`:

```ruby
require "minitest/autorun"
require "rack/test"
require "json"
require_relative "../worker"

class TestWorker < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
  end

  # Health Check Tests

  def test_health_check_returns_200
    get "/health"
    assert_equal 200, last_response.status
  end

  def test_health_check_validates_environment
    get "/health"
    body = JSON.parse(last_response.body)

    assert_equal "healthy", body["status"]
    assert body["checks"]["env_vars_set"]
  end

  # Request Validation Tests

  def test_missing_title_returns_400
    post "/process", task_payload_without(:title), json_headers
    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_includes body["message"], "title"
  end

  def test_missing_author_returns_400
    post "/process", task_payload_without(:author), json_headers
    assert_equal 400, last_response.status
  end

  def test_missing_description_returns_400
    post "/process", task_payload_without(:description), json_headers
    assert_equal 400, last_response.status
  end

  def test_missing_gcs_path_returns_400
    post "/process", task_payload_without(:gcs_path), json_headers
    assert_equal 400, last_response.status
  end

  private

  def json_headers
    { "CONTENT_TYPE" => "application/json" }
  end

  def valid_task_payload
    {
      title: "Test Title",
      author: "Test Author",
      description: "Test Description",
      gcs_path: "staging/test.md"
    }.to_json
  end

  def task_payload_without(key)
    payload = {
      title: "Test Title",
      author: "Test Author",
      description: "Test Description",
      gcs_path: "staging/test.md"
    }
    payload.delete(key)
    payload.to_json
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_worker.rb
```

**Step 3: Create the worker app**

Create `worker.rb`:

```ruby
require "sinatra"
require "sinatra/json"
require "json"
require_relative "lib/file_manager"
require_relative "lib/episode_processor"

# Configure Sinatra
set :port, ENV.fetch("PORT", 8080)
set :bind, "0.0.0.0"
set :show_exceptions, false

# Health check endpoint with environment validation
get "/health" do
  required_vars = %w[
    GOOGLE_CLOUD_PROJECT
    GOOGLE_CLOUD_BUCKET
  ]

  missing_vars = required_vars.reject { |var| ENV[var] }

  if missing_vars.empty?
    json status: "healthy", checks: { env_vars_set: true }
  else
    halt 500, json(
      status: "unhealthy",
      checks: { env_vars_set: false },
      missing_vars: missing_vars
    )
  end
end

# Episode processing endpoint (invoked by Cloud Tasks)
post "/process" do
  # Step 1: Parse JSON payload from Cloud Tasks
  request.body.rewind
  payload = JSON.parse(request.body.read)

  # Step 2: Validate payload
  validation_error = validate_payload(payload)
  if validation_error
    halt 400, json(status: "error", message: validation_error)
  end

  # Step 3: Extract parameters
  title = payload["title"]
  author = payload["author"]
  description = payload["description"]
  gcs_path = payload["gcs_path"]

  logger.info "Processing episode: #{title}"
  logger.info "Downloading from GCS: #{gcs_path}"

  # Step 4: Download markdown from GCS staging
  file_manager = FileManager.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
  markdown_content = file_manager.download_from_staging(gcs_path)

  # Step 5: Process episode
  processor = EpisodeProcessor.new
  processor.process(title, author, description, markdown_content)

  # Step 6: Cleanup staging file
  processor.cleanup_staging(gcs_path)

  # Step 7: Return success
  logger.info "Episode processed successfully: #{title}"
  json status: "success", message: "Episode processed successfully"
rescue JSON::ParserError => e
  logger.error "Invalid JSON payload: #{e.message}"
  halt 400, json(status: "error", message: "Invalid JSON payload")
rescue StandardError => e
  logger.error "Error processing episode: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end

# Validate task payload
def validate_payload(payload)
  return "Missing required field: title" unless payload["title"]
  return "Missing required field: author" unless payload["author"]
  return "Missing required field: description" unless payload["description"]
  return "Missing required field: gcs_path" unless payload["gcs_path"]

  nil # No errors
end
```

**Step 4: Run tests**

```bash
ruby test/test_worker.rb
rake test
rake rubocop
```

**Commit**:
```bash
git add worker.rb test/test_worker.rb
git commit -m "Add worker service for episode processing"
```

---

#### Task 4.6: Create Worker Dockerfile

**What**: Create a Dockerfile for the Worker service.

**Files to create**:
- `Dockerfile.worker`

**What to do**:

Create `Dockerfile.worker`:
```dockerfile
# Use official Ruby image
FROM ruby:3.4.5-slim

# Install dependencies
RUN apt-get update -qq && \
    apt-get install -y build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development' && \
    bundle install

# Copy application code
COPY lib/ ./lib/
COPY config/ ./config/
COPY worker.rb ./

# Create output directory
RUN mkdir -p output

# Expose port
EXPOSE 8080

# Start application
CMD ["bundle", "exec", "ruby", "worker.rb"]
```

Update `.dockerignore`:
```
.git
.env
.DS_Store
*.md
docs/
test/
output/*.mp3
input/*.md
.rubocop.yml
Rakefile
generate.rb
test_single_chunk.rb
.ruby-lsp/
very-normal-text-to-speech-*.json
api.rb
```

**Testing**:

```bash
docker build -f Dockerfile.worker -t podcast-worker .
```

**Commit**:
```bash
git add Dockerfile.worker .dockerignore
git commit -m "Add Dockerfile for worker service"
```

---

### Phase 5: Infrastructure & Deployment

#### Task 5.1: Create Infrastructure Setup Script

**What**: Create a script to set up Google Cloud infrastructure (Cloud Tasks queue).

**Why**: Automates the one-time infrastructure setup, making it repeatable and documented.

**Files to create**:
- `bin/setup-infrastructure`

**What to do**:

Create `bin/setup-infrastructure`:
```bash
#!/bin/bash
set -e

echo "================================"
echo "Setting up Cloud Infrastructure"
echo "================================"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed"
    echo "Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    echo "Copy .env.example to .env and configure it"
    exit 1
fi

# Check required environment variables
if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    echo "Error: GOOGLE_CLOUD_PROJECT not set in .env"
    exit 1
fi

PROJECT_ID=$GOOGLE_CLOUD_PROJECT
LOCATION=${CLOUD_TASKS_LOCATION:-us-central1}
QUEUE_NAME=${CLOUD_TASKS_QUEUE:-episode-processing}

echo ""
echo "Project: $PROJECT_ID"
echo "Location: $LOCATION"
echo "Queue: $QUEUE_NAME"
echo ""

# Enable required APIs
echo "Enabling Google Cloud APIs..."
gcloud services enable run.googleapis.com --project=$PROJECT_ID
gcloud services enable cloudtasks.googleapis.com --project=$PROJECT_ID
echo "✓ APIs enabled"

# Create Cloud Tasks queue
echo ""
echo "Creating Cloud Tasks queue..."
if gcloud tasks queues describe $QUEUE_NAME --location=$LOCATION --project=$PROJECT_ID &> /dev/null; then
    echo "✓ Queue already exists: $QUEUE_NAME"
else
    gcloud tasks queues create $QUEUE_NAME \
        --location=$LOCATION \
        --project=$PROJECT_ID \
        --max-attempts=3 \
        --max-retry-duration=1h
    echo "✓ Queue created: $QUEUE_NAME"
fi

echo ""
echo "================================"
echo "Infrastructure setup complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "  1. Deploy services: ./bin/deploy"
echo "  2. Test the API: see examples/ directory"
```

Make it executable:
```bash
chmod +x bin/setup-infrastructure
```

**Testing**: Run the script:
```bash
./bin/setup-infrastructure
```

**Commit**:
```bash
git add bin/setup-infrastructure
git commit -m "Add infrastructure setup script for Cloud Tasks"
```

---

#### Task 5.2: Update Environment Variables

**What**: Update .env.example with all required variables.

**Files to modify**:
- `.env.example`

**What to do**:

Update `.env.example`:
```bash
# Google Cloud Configuration
# Required for both TTS and Cloud Storage functionality

# Your Google Cloud Project ID
GOOGLE_CLOUD_PROJECT=your-project-id

# Google Cloud Storage bucket name
GOOGLE_CLOUD_BUCKET=your-bucket-name

# Path to your Google Cloud service account credentials JSON file
GOOGLE_APPLICATION_CREDENTIALS=./path/to/your-credentials.json

# API Configuration
# Generate with: openssl rand -hex 32
API_SECRET_TOKEN=your-secret-token-here

# Cloud Tasks Configuration
CLOUD_TASKS_LOCATION=us-central1
CLOUD_TASKS_QUEUE=episode-processing

# Worker Service URL (set after worker is deployed)
# Format: https://podcast-worker-XXXXXXXX.run.app/process
WORKER_URL=

# TTS Voice (optional, defaults to en-GB-Chirp3-HD-Enceladus)
TTS_VOICE=en-GB-Chirp3-HD-Enceladus

# Port for local development (optional, defaults to 8080)
PORT=8080
```

Update your local `.env`:
```bash
echo "API_SECRET_TOKEN=$(openssl rand -hex 32)" >> .env
echo "CLOUD_TASKS_LOCATION=us-central1" >> .env
echo "CLOUD_TASKS_QUEUE=episode-processing" >> .env
# WORKER_URL will be added after deployment
```

**Commit**:
```bash
git add .env.example
git commit -m "Add all required environment variables"
```

---

#### Task 5.3: Create Unified Deployment Script

**What**: Create a single deployment script that handles both services.

**Why**: DRY - avoids duplication between separate deployment scripts.

**Files to create**:
- `bin/deploy`

**What to do**:

Create `bin/deploy`:
```bash
#!/bin/bash
set -e

# Default values
SERVICE=""
REGION="us-central1"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: ./bin/deploy --service <api|worker|all> [--region REGION]"
            echo ""
            echo "Options:"
            echo "  --service    Which service to deploy (api, worker, or all)"
            echo "  --region     Google Cloud region (default: us-central1)"
            echo ""
            echo "Examples:"
            echo "  ./bin/deploy --service all"
            echo "  ./bin/deploy --service api"
            echo "  ./bin/deploy --service worker"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if service is specified
if [ -z "$SERVICE" ]; then
    echo "Error: --service is required"
    echo "Use --help for usage information"
    exit 1
fi

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Validate required env vars
if [ -z "$GOOGLE_CLOUD_PROJECT" ] || [ -z "$GOOGLE_CLOUD_BUCKET" ] || [ -z "$API_SECRET_TOKEN" ]; then
    echo "Error: Required environment variables not set"
    echo "Check your .env file for: GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_BUCKET, API_SECRET_TOKEN"
    exit 1
fi

# Deploy worker function
deploy_worker() {
    echo "================================"
    echo "Deploying Worker Service"
    echo "================================"

    gcloud run deploy podcast-worker \
        --source . \
        --dockerfile Dockerfile.worker \
        --project $GOOGLE_CLOUD_PROJECT \
        --region $REGION \
        --platform managed \
        --allow-unauthenticated \
        --memory 2Gi \
        --timeout 600s \
        --max-instances 1 \
        --min-instances 0 \
        --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
        --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET"

    echo "✓ Worker service deployed"
}

# Deploy API function
deploy_api() {
    echo "================================"
    echo "Deploying API Service"
    echo "================================"

    # Get worker URL if not set
    if [ -z "$WORKER_URL" ]; then
        echo "Getting worker URL..."
        WORKER_URL=$(gcloud run services describe podcast-worker \
            --region $REGION \
            --project $GOOGLE_CLOUD_PROJECT \
            --format 'value(status.url)')/process

        # Update .env with worker URL
        if ! grep -q "^WORKER_URL=" .env; then
            echo "WORKER_URL=$WORKER_URL" >> .env
        fi
    fi

    gcloud run deploy podcast-api \
        --source . \
        --dockerfile Dockerfile.api \
        --project $GOOGLE_CLOUD_PROJECT \
        --region $REGION \
        --platform managed \
        --allow-unauthenticated \
        --memory 1Gi \
        --timeout 60s \
        --max-instances 1 \
        --min-instances 0 \
        --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
        --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET" \
        --set-env-vars "API_SECRET_TOKEN=$API_SECRET_TOKEN" \
        --set-env-vars "WORKER_URL=$WORKER_URL" \
        --set-env-vars "CLOUD_TASKS_LOCATION=${CLOUD_TASKS_LOCATION:-us-central1}" \
        --set-env-vars "CLOUD_TASKS_QUEUE=${CLOUD_TASKS_QUEUE:-episode-processing}"

    echo "✓ API service deployed"
}

# Deploy based on service argument
case $SERVICE in
    worker)
        deploy_worker
        ;;
    api)
        deploy_api
        ;;
    all)
        deploy_worker
        deploy_api

        # Show summary
        API_URL=$(gcloud run services describe podcast-api \
            --region $REGION \
            --project $GOOGLE_CLOUD_PROJECT \
            --format 'value(status.url)')

        echo ""
        echo "================================"
        echo "Deployment Complete!"
        echo "================================"
        echo ""
        echo "API URL: $API_URL"
        echo "Worker URL: ${WORKER_URL%/process}"
        echo ""
        echo "Test your API:"
        echo "  See examples/ directory for curl commands"
        ;;
    *)
        echo "Error: Invalid service '$SERVICE'"
        echo "Must be: api, worker, or all"
        exit 1
        ;;
esac
```

Make it executable:
```bash
chmod +x bin/deploy
```

**Testing**:
```bash
./bin/deploy --help
```

**Commit**:
```bash
git add bin/deploy
git commit -m "Add unified deployment script for both services"
```

---

#### Task 5.4: End-to-End Testing

**What**: Deploy both services and test the complete flow.

**Why**: Verify everything works together in production.

**What to do**:

1. **Run infrastructure setup** (if not done):
   ```bash
   ./bin/setup-infrastructure
   ```

2. **Deploy both services**:
   ```bash
   ./bin/deploy --service all
   ```

3. **Create a test markdown file**:
   ```bash
   mkdir -p /tmp/podcast-test
   cat > /tmp/podcast-test/test-episode.md << 'EOF'
   # Test Episode

   This is a test episode to verify the complete publishing pipeline.

   ## Section One

   The API should upload this to GCS staging, then enqueue a task.

   ## Section Two

   The worker should pick up the task, generate TTS audio, and publish to the RSS feed.
   EOF
   ```

4. **Get your API URL**:
   ```bash
   API_URL=$(gcloud run services describe podcast-api \
     --region us-central1 \
     --format 'value(status.url)')
   echo $API_URL
   ```

5. **Test health checks**:
   ```bash
   # API health
   curl $API_URL/health

   # Worker health
   WORKER_URL=$(gcloud run services describe podcast-worker \
     --region us-central1 \
     --format 'value(status.url)')
   curl $WORKER_URL/health
   ```

6. **Submit test episode**:
   ```bash
   source .env
   curl -X POST $API_URL/publish \
     -H "Authorization: Bearer $API_SECRET_TOKEN" \
     -F "title=Test Episode $(date +%s)" \
     -F "author=API Tester" \
     -F "description=Testing the complete publishing pipeline" \
     -F "content=@/tmp/podcast-test/test-episode.md"
   ```

   Should return immediately:
   ```json
   {"status":"success","message":"Episode submitted for processing"}
   ```

7. **Monitor processing** (wait 30-60 seconds):
   ```bash
   # Check API logs
   gcloud run logs read podcast-api --region us-central1 --limit 20

   # Check worker logs (look for "Episode published successfully")
   gcloud run logs read podcast-worker --region us-central1 --limit 50
   ```

8. **Verify episode published**:
   ```bash
   # Check RSS feed
   curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml | grep "Test Episode"

   # List episodes
   gsutil ls gs://$GOOGLE_CLOUD_BUCKET/episodes/
   gsutil ls gs://$GOOGLE_CLOUD_BUCKET/input/
   ```

9. **Check Cloud Tasks queue**:
   ```bash
   gcloud tasks queues describe episode-processing --location=us-central1
   ```

**Success Criteria**:
- ✅ Both health checks return "healthy"
- ✅ API returns 200 immediately
- ✅ Worker logs show successful processing
- ✅ MP3 file appears in GCS episodes/
- ✅ Markdown appears in GCS input/
- ✅ Episode appears in RSS feed
- ✅ No staging file left in GCS

**Commit**:
```bash
git commit --allow-empty -m "Complete end-to-end testing of publishing pipeline"
```

---

### Phase 6: Documentation & Examples

#### Task 6.1: Create Example Scripts

**What**: Create example curl commands and scripts for using the API.

**Why**: Makes it easy for users (including future you) to test and use the API.

**Files to create**:
- `examples/publish-episode.sh`
- `examples/README.md`

**What to do**:

Create `examples/` directory:
```bash
mkdir -p examples
```

Create `examples/publish-episode.sh`:
```bash
#!/bin/bash
set -e

# Load environment variables
if [ -f ../.env ]; then
    source ../.env
else
    echo "Error: .env file not found in parent directory"
    exit 1
fi

# Check arguments
if [ $# -lt 4 ]; then
    echo "Usage: ./publish-episode.sh TITLE AUTHOR DESCRIPTION MARKDOWN_FILE"
    echo ""
    echo "Example:"
    echo "  ./publish-episode.sh \"My Episode\" \"John Doe\" \"Episode description\" article.md"
    exit 1
fi

TITLE="$1"
AUTHOR="$2"
DESCRIPTION="$3"
MARKDOWN_FILE="$4"

# Check if file exists
if [ ! -f "$MARKDOWN_FILE" ]; then
    echo "Error: File not found: $MARKDOWN_FILE"
    exit 1
fi

# Get API URL
API_URL=$(gcloud run services describe podcast-api \
    --region us-central1 \
    --project $GOOGLE_CLOUD_PROJECT \
    --format 'value(status.url)' 2>/dev/null)

if [ -z "$API_URL" ]; then
    echo "Error: Could not get API URL. Is the service deployed?"
    exit 1
fi

echo "Publishing episode..."
echo "Title: $TITLE"
echo "Author: $AUTHOR"
echo "File: $MARKDOWN_FILE"
echo ""

# Submit episode
RESPONSE=$(curl -s -X POST $API_URL/publish \
    -H "Authorization: Bearer $API_SECRET_TOKEN" \
    -F "title=$TITLE" \
    -F "author=$AUTHOR" \
    -F "description=$DESCRIPTION" \
    -F "content=@$MARKDOWN_FILE")

echo "Response: $RESPONSE"
echo ""

# Check if successful
if echo "$RESPONSE" | grep -q '"status":"success"'; then
    echo "✓ Episode submitted for processing"
    echo ""
    echo "Monitor processing:"
    echo "  gcloud run logs read podcast-worker --region us-central1 --limit 50"
    echo ""
    echo "Check RSS feed (after ~60 seconds):"
    echo "  curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml"
else
    echo "✗ Submission failed"
    exit 1
fi
```

Create `examples/README.md`:
```markdown
# API Examples

Example scripts and commands for using the Podcast Publishing API.

## Prerequisites

1. Services must be deployed: `./bin/deploy --service all`
2. Environment variables configured in `.env`

## Publishing an Episode

### Using the Script

```bash
cd examples
./publish-episode.sh "Episode Title" "Author Name" "Episode description" path/to/article.md
```

### Using curl Directly

```bash
# Get your API URL
API_URL=$(gcloud run services describe podcast-api \
  --region us-central1 \
  --format 'value(status.url)')

# Submit episode
curl -X POST $API_URL/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=My Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description goes here" \
  -F "content=@article.md"
```

## Health Checks

Check if services are running:

```bash
# API health
curl $(gcloud run services describe podcast-api --region us-central1 --format 'value(status.url)')/health

# Worker health
curl $(gcloud run services describe podcast-worker --region us-central1 --format 'value(status.url)')/health
```

## Monitoring

View logs:

```bash
# API logs
gcloud run logs read podcast-api --region us-central1 --limit 50

# Worker logs (shows processing details)
gcloud run logs read podcast-worker --region us-central1 --limit 50
```

Check Cloud Tasks queue:

```bash
gcloud tasks queues describe episode-processing --location=us-central1
```

## Verifying Published Episodes

Check RSS feed:

```bash
curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml
```

List files in GCS:

```bash
# Episodes (MP3 files)
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/episodes/

# Archived markdown
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/input/
```
```

Make the script executable:
```bash
chmod +x examples/publish-episode.sh
```

**Commit**:
```bash
git add examples/
git commit -m "Add example scripts for publishing episodes"
```

---

#### Task 6.2: Create API Documentation

**What**: Create comprehensive API documentation.

**Why**: Documents the API endpoints, authentication, and usage for users.

**Files to create**:
- `docs/API.md`

**What to do**:

Create `docs/API.md`:
```markdown
# Podcast Publishing API Documentation

## Overview

HTTP API for publishing podcast episodes. Submit episode metadata and markdown content via POST request, and the system automatically generates audio, uploads to cloud storage, and updates the RSS feed.

## Architecture

The system uses two Cloud Run services connected by Google Cloud Tasks:

1. **API Service**: Accepts requests, validates input, uploads to GCS, enqueues tasks
2. **Worker Service**: Processes episodes (TTS, publish, RSS update)

```
User → API Service → Cloud Tasks → Worker Service → Published Episode
```

## Base URL

Get your API URL after deployment:
```bash
gcloud run services describe podcast-api --region us-central1 --format 'value(status.url)'
```

## Authentication

All requests require Bearer token authentication:

```http
Authorization: Bearer YOUR_SECRET_TOKEN
```

Set `API_SECRET_TOKEN` in your `.env` file.

## Endpoints

### Health Check

```http
GET /health
```

Returns service health status and validates environment configuration.

**Response (200 OK):**
```json
{
  "status": "healthy",
  "checks": {
    "env_vars_set": true
  }
}
```

**Response (500 Error):**
```json
{
  "status": "unhealthy",
  "checks": {
    "env_vars_set": false
  },
  "missing_vars": ["WORKER_URL"]
}
```

### Publish Episode

```http
POST /publish
```

Submit a new podcast episode for processing.

**Request Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| title | string | Yes | Episode title |
| author | string | Yes | Episode author name |
| description | string | Yes | Episode description |
| content | file | Yes | Markdown file containing article body |

**Request Example:**

```bash
curl -X POST https://YOUR_API_URL.run.app/publish \
  -H "Authorization: Bearer YOUR_SECRET_TOKEN" \
  -F "title=The Programmer Identity Crisis" \
  -F "author=Unknown" \
  -F "description=A reflection on AI and programming" \
  -F "content=@article.md"
```

**Success Response (200 OK):**

```json
{
  "status": "success",
  "message": "Episode submitted for processing"
}
```

**Error Responses:**

| Status | Response | Description |
|--------|----------|-------------|
| 400 | `{"status":"error","message":"Missing required field: title"}` | Missing or invalid parameters |
| 401 | `{"status":"error","message":"Unauthorized..."}` | Invalid authentication |
| 500 | `{"status":"error","message":"Internal server error"}` | Server error |

## Processing Flow

After successful submission (200 response):

1. Episode markdown uploaded to GCS staging
2. Task enqueued to Cloud Tasks
3. API returns success immediately
4. Worker service triggered by Cloud Tasks
5. Worker downloads markdown from GCS
6. Text-to-speech audio generated (30-60 seconds)
7. Audio file uploaded to GCS
8. RSS feed updated
9. Markdown archived to GCS input/
10. Staging file cleaned up

**Total time**: 30-90 seconds depending on article length

## Monitoring

**View API logs:**
```bash
gcloud run logs read podcast-api --region us-central1 --limit 50
```

**View Worker logs:**
```bash
gcloud run logs read podcast-worker --region us-central1 --limit 50
```

**Check Cloud Tasks:**
```bash
gcloud tasks queues describe episode-processing --location=us-central1
```

**Verify RSS feed:**
```bash
curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml
```

## Error Handling

Processing errors are logged but not returned to the client (async processing).

**Common errors:**

- **TTS rate limit**: Cloud Tasks retries automatically (up to 3 times)
- **Content filter**: Check worker logs for details
- **Upload failure**: Verify GCS permissions
- **Task enqueue failure**: Check queue exists and has capacity

## Cost Estimates

**Monthly costs** (personal use, ~10 episodes):

- Cloud Run (API): $0-2
- Cloud Run (Worker): $0-3
- Cloud Tasks: $0 (free tier)
- Cloud TTS: ~$1-5 (depending on article length)
- Cloud Storage: $0-1

**Total: ~$5-10/month**

## Local Development

See `examples/README.md` for local testing instructions.

Note: Even local testing requires Cloud Tasks queue in GCP.

## Deployment

See main README for deployment instructions.
```

**Commit**:
```bash
git add docs/API.md
git commit -m "Add comprehensive API documentation"
```

---

#### Task 6.3: Update README

**What**: Update main README with API overview and links.

**Why**: Provides entry point to documentation for users.

**Files to modify**:
- `README.md`

**What to do**:

Add after the "Usage" section in `README.md`:

```markdown
## API Usage

Publish episodes via HTTP API for automation:

```bash
curl -X POST https://your-api-service.run.app/publish \
  -H "Authorization: Bearer YOUR_SECRET_TOKEN" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@article.md"
```

Returns immediately. Processing happens in background (~30-60 seconds).

See:
- [API Documentation](docs/API.md) - Full API reference
- [Examples](examples/README.md) - Example scripts and commands

### Architecture

**Two serverless services:**
- **API Service**: Fast endpoint (validates, uploads, enqueues)
- **Worker Service**: Heavy processing (TTS, RSS publishing)
- **Cloud Tasks**: Reliable queue connecting them

### Setup & Deployment

1. **Setup infrastructure** (one-time):
   ```bash
   ./bin/setup-infrastructure
   ```

2. **Deploy services**:
   ```bash
   ./bin/deploy --service all
   ```

3. **Publish an episode**:
   ```bash
   cd examples
   ./publish-episode.sh "Title" "Author" "Description" article.md
   ```

See [API Documentation](docs/API.md) for detailed setup instructions.
```

**Commit**:
```bash
git add README.md
git commit -m "Update README with API usage and deployment info"
```

---

## Summary

### What We Built

1. **Shared Utilities**: FilenameGenerator module
2. **API Service**: Fast Sinatra app with auth, validation, health checks
3. **Worker Components**: FileManager, AudioGenerator, FeedPublisher, EpisodeProcessor
4. **Worker Service**: Heavy-duty Sinatra app for TTS processing
5. **Infrastructure Scripts**: Setup and unified deployment
6. **Documentation**: API docs, examples, updated README

### Architecture

```
User → API (Cloud Run) → Cloud Tasks → Worker (Cloud Run) → [TTS, GCS, RSS] → Published Episode
```

### Key Files

**Libraries:**
- `lib/filename_generator.rb` - Shared filename generation
- `lib/file_manager.rb` - GCS and local file operations
- `lib/audio_generator.rb` - TTS audio generation
- `lib/feed_publisher.rb` - Podcast RSS publishing
- `lib/episode_processor.rb` - Main orchestrator

**Services:**
- `api.rb` - API Sinatra service
- `worker.rb` - Worker Sinatra service
- `Dockerfile.api` - API container
- `Dockerfile.worker` - Worker container

**Infrastructure:**
- `bin/setup-infrastructure` - One-time GCP setup
- `bin/deploy` - Unified deployment script

**Documentation:**
- `docs/API.md` - API reference
- `examples/` - Usage examples
- `README.md` - Overview and quick start

### Task Count

- **Phase 1**: 1 task - Dependencies
- **Phase 2**: 1 task - Shared utilities
- **Phase 3**: 2 tasks - API service
- **Phase 4**: 6 tasks - Worker components and service
- **Phase 5**: 4 tasks - Infrastructure and deployment
- **Phase 6**: 3 tasks - Documentation and examples

**Total: 17 tasks**

### Deployment

```bash
# One-time setup
./bin/setup-infrastructure

# Deploy both services
./bin/deploy --service all

# Test
cd examples
./publish-episode.sh "Test" "Author" "Description" article.md
```

### Costs

~$5-10/month for moderate use (within free tiers for most services)

### Key Improvements from Review

✅ Removed TaskEnqueuer abstraction (YAGNI)
✅ Extracted FilenameGenerator (DRY)
✅ Split worker into focused classes (SRP)
✅ Added health checks with config validation
✅ Unified deployment script
✅ Infrastructure setup automation
✅ Comprehensive examples and docs
✅ Ensure blocks for cleanup
✅ Detailed logging throughout

---

End of implementation plan.
