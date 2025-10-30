# Implementation Plan: Podcast Publishing API

## Overview

This plan details how to build a minimal HTTP API that accepts podcast episode submissions via cURL and publishes them to the podcast feed. The system uses two Google Cloud Run services connected by Google Cloud Tasks for serverless asynchronous processing.

### What We're Building

Two Cloud Run services:

**Service 1: API Service** - Fast, accepts requests:
1. Accepts authentication via Bearer token
2. Receives episode metadata (title, author, description) and markdown content file
3. Uploads content to GCS staging area
4. Enqueues job to Google Cloud Tasks
5. Returns immediate success/error response

**Service 2: Worker Service** - Heavy lifting:
1. Triggered by Cloud Tasks
2. Processes markdown to plain text
3. Generates TTS audio
4. Publishes to podcast feed
5. Logs results to Google Cloud Logging

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
│ 4. Upload to GCS        │
│ 5. Update RSS Feed      │
│ 6. Log Results          │
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

### Phase 1: Cloud Tasks Infrastructure

#### Task 1.1: Add Google Cloud Tasks Gem

**What**: Add the Google Cloud Tasks gem for enqueueing jobs.

**Why**: We need Cloud Tasks to communicate between the API and Worker services asynchronously.

**Files to modify**:
- `Gemfile`

**What to do**:

1. Add Cloud Tasks gem to `Gemfile`:
   ```ruby
   # Add after google-cloud-storage
   gem "google-cloud-tasks", "~> 2.0"
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Verify installation:
   ```bash
   bundle list | grep google-cloud-tasks
   # Should show: google-cloud-tasks (x.x.x)
   ```

**Testing**: No tests needed yet - just dependency installation.

**Commit**:
```bash
git add Gemfile Gemfile.lock
git commit -m "Add google-cloud-tasks for job queue"
```

---

#### Task 1.2: Create Task Queue Helper (Test First)

**What**: Create a helper class for enqueueing tasks to Cloud Tasks.

**Why**: This abstracts Cloud Tasks API calls and makes the code easier to test and maintain.

**Files to create**:
- `test/test_task_enqueuer.rb` (create this FIRST)
- `lib/task_enqueuer.rb` (create this AFTER tests)

**What to do**:

**Step 1: Write the test first** (TDD principle)

Create `test/test_task_enqueuer.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/task_enqueuer"

class TestTaskEnqueuer < Minitest::Test
  def setup
    @enqueuer = TaskEnqueuer.new(
      project_id: "test-project",
      location: "us-central1",
      queue_name: "test-queue",
      worker_url: "https://test-worker.run.app/process"
    )
  end

  def test_initialization
    assert_equal "test-project", @enqueuer.project_id
    assert_equal "us-central1", @enqueuer.location
    assert_equal "test-queue", @enqueuer.queue_name
    assert_equal "https://test-worker.run.app/process", @enqueuer.worker_url
  end

  def test_formats_queue_path_correctly
    expected = "projects/test-project/locations/us-central1/queues/test-queue"
    assert_equal expected, @enqueuer.queue_path
  end

  def test_builds_task_payload
    payload = @enqueuer.build_payload(
      title: "Test Title",
      author: "Test Author",
      description: "Test Description",
      gcs_path: "staging/test.md"
    )

    assert_equal "Test Title", payload[:title]
    assert_equal "Test Author", payload[:author]
    assert_equal "Test Description", payload[:description]
    assert_equal "staging/test.md", payload[:gcs_path]
  end
end
```

**Step 2: Run the test (it should fail)**

```bash
ruby test/test_task_enqueuer.rb
# Expected: LoadError - cannot load such file -- ../lib/task_enqueuer
```

**Step 3: Create the implementation**

Create `lib/task_enqueuer.rb`:

```ruby
require "google/cloud/tasks/v2"
require "json"

# Helper class for enqueueing tasks to Google Cloud Tasks
# Abstracts the Cloud Tasks API for easier testing and maintenance
class TaskEnqueuer
  attr_reader :project_id, :location, :queue_name, :worker_url

  # Initialize the task enqueuer
  # @param project_id [String] Google Cloud project ID
  # @param location [String] Cloud Tasks queue location (e.g., "us-central1")
  # @param queue_name [String] Name of the task queue
  # @param worker_url [String] URL of the worker service to invoke
  def initialize(project_id:, location:, queue_name:, worker_url:)
    @project_id = project_id
    @location = location
    @queue_name = queue_name
    @worker_url = worker_url
    @client = Google::Cloud::Tasks::V2::CloudTasks::Client.new
  end

  # Enqueue a new episode processing task
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param gcs_path [String] Path to markdown file in GCS
  # @return [String] Task name
  def enqueue(title:, author:, description:, gcs_path:)
    task = build_task(
      title: title,
      author: author,
      description: description,
      gcs_path: gcs_path
    )

    response = @client.create_task(parent: queue_path, task: task)
    response.name
  end

  # Get the full queue path for Cloud Tasks API
  # @return [String] Full queue path
  def queue_path
    @client.queue_path(project: @project_id, location: @location, queue: @queue_name)
  end

  # Build the payload for the task
  # @return [Hash] Task payload
  def build_payload(title:, author:, description:, gcs_path:)
    {
      title: title,
      author: author,
      description: description,
      gcs_path: gcs_path
    }
  end

  private

  # Build a Cloud Tasks task
  def build_task(title:, author:, description:, gcs_path:)
    payload = build_payload(
      title: title,
      author: author,
      description: description,
      gcs_path: gcs_path
    )

    {
      http_request: {
        http_method: "POST",
        url: @worker_url,
        headers: {
          "Content-Type" => "application/json"
        },
        body: payload.to_json
      }
    }
  end
end
```

**Step 4: Run tests**

```bash
ruby test/test_task_enqueuer.rb
# Should pass now
```

**Step 5: Run all tests**

```bash
rake test
```

**Step 6: Check code style**

```bash
rake rubocop
# Fix any issues reported
```

**Testing Notes**:
- We test the public interface, not the actual Cloud Tasks API call
- Full integration testing will happen when we deploy to Cloud Run
- The actual enqueueing will be tested in the API service tests

**Commit**:
```bash
git add lib/task_enqueuer.rb test/test_task_enqueuer.rb
git commit -m "Add TaskEnqueuer for Cloud Tasks integration"
```

---

### Phase 2: API Service

#### Task 2.1: Add Sinatra Dependencies

**What**: Add Sinatra and related gems for building the web API.

**Files to modify**:
- `Gemfile`

**What to do**:

1. Add Sinatra gems to `Gemfile`:
   ```ruby
   # Add after google-cloud-tasks
   gem "sinatra"
   gem "sinatra-contrib" # Adds useful helpers like json
   gem "puma"            # Production web server
   gem "rack-test", group: :test  # For testing Sinatra apps
   ```

2. Install:
   ```bash
   bundle install
   ```

**Commit**:
```bash
git add Gemfile Gemfile.lock
git commit -m "Add sinatra and puma for web API"
```

---

#### Task 2.2: Create API Service (Test First)

**What**: Create the API Sinatra application with the `/publish` endpoint.

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
    get "/"
    assert_equal 200, last_response.status
  end

  def test_health_check_returns_json
    get "/"
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
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

  # Success Tests

  def test_valid_request_returns_200
    mock_gcs_and_tasks do
      post "/publish", valid_params, auth_header
      assert_equal 200, last_response.status
    end
  end

  def test_valid_request_returns_success_json
    mock_gcs_and_tasks do
      post "/publish", valid_params, auth_header

      body = JSON.parse(last_response.body)
      assert_equal "success", body["status"]
      assert_equal "Episode submitted for processing", body["message"]
    end
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

  # Mock GCS and Cloud Tasks to avoid actual API calls in tests
  def mock_gcs_and_tasks
    # Stub the actual API calls that happen in the endpoint
    stub_gcs_upload
    stub_task_enqueue
    yield
  end

  def stub_gcs_upload
    # In real implementation, we'll use dependency injection or test doubles
    # For now, this is a placeholder
  end

  def stub_task_enqueue
    # In real implementation, we'll use dependency injection or test doubles
    # For now, this is a placeholder
  end
end
```

**Step 2: Run tests (they should fail)**

```bash
ruby test/test_api.rb
# Expected: LoadError - cannot load api.rb
```

**Step 3: Create the Sinatra app**

Create `api.rb` in the project root:

```ruby
require "sinatra"
require "sinatra/json"
require_relative "lib/gcs_uploader"
require_relative "lib/task_enqueuer"

# Configure Sinatra
set :port, ENV.fetch("PORT", 8080)
set :bind, "0.0.0.0"
set :show_exceptions, false # We'll handle errors ourselves

# Health check endpoint for Cloud Run
get "/" do
  json status: "ok", message: "Podcast Publishing API"
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
  filename = generate_filename(title)
  staging_path = "staging/#{filename}.md"

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
  gcs.upload_content(content: content, remote_path: staging_path)

  staging_path
end

# Enqueue task to Cloud Tasks
def enqueue_processing_task(title, author, description, gcs_path)
  enqueuer = TaskEnqueuer.new(
    project_id: ENV.fetch("GOOGLE_CLOUD_PROJECT"),
    location: ENV.fetch("CLOUD_TASKS_LOCATION", "us-central1"),
    queue_name: ENV.fetch("CLOUD_TASKS_QUEUE", "episode-processing"),
    worker_url: ENV.fetch("WORKER_URL")
  )

  enqueuer.enqueue(
    title: title,
    author: author,
    description: description,
    gcs_path: gcs_path
  )
end

# Generate filename from title: "My Title" -> "2025-10-28-my-title"
def generate_filename(title)
  date = Time.now.strftime("%Y-%m-%d")
  slug = title.downcase
             .gsub(/[^\w\s-]/, "") # Remove special chars
             .gsub(/\s+/, "-")      # Spaces to hyphens
             .gsub(/-+/, "-")       # Collapse multiple hyphens
             .strip
  "#{date}-#{slug}"
end
```

**Step 4: Run tests**

```bash
ruby test/test_api.rb
# Should pass (with mocking)
```

**Step 5: Run all tests**

```bash
rake test
```

**Step 6: Run rubocop**

```bash
rake rubocop
# Fix any issues
```

**Commit**:
```bash
git add api.rb test/test_api.rb
git commit -m "Add API service with /publish endpoint"
```

---

#### Task 2.3: Create API Dockerfile

**What**: Create a Dockerfile for the API service.

**Files to create**:
- `Dockerfile.api`
- `.dockerignore`

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

Create `.dockerignore` (if not exists):
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

**Testing Dockerfile locally**:

1. Build the image:
   ```bash
   docker build -f Dockerfile.api -t podcast-api .
   ```

2. Run the container:
   ```bash
   docker run -p 8080:8080 \
     -e API_SECRET_TOKEN=test123 \
     -e GOOGLE_CLOUD_PROJECT=your-project \
     -e GOOGLE_CLOUD_BUCKET=your-bucket \
     -e GOOGLE_APPLICATION_CREDENTIALS=/app/credentials.json \
     -e WORKER_URL=https://test-worker.run.app/process \
     -v $(pwd)/your-credentials.json:/app/credentials.json:ro \
     podcast-api
   ```

3. Test with curl:
   ```bash
   curl http://localhost:8080/
   # Should return: {"status":"ok","message":"Podcast Publishing API"}
   ```

**Commit**:
```bash
git add Dockerfile.api .dockerignore
git commit -m "Add Dockerfile for API service"
```

---

### Phase 3: Worker Service

#### Task 3.1: Create Episode Processor Class (Test First)

**What**: Create a class that processes episodes (TTS, upload, RSS).

**Why**: This encapsulates all the publishing logic that the worker will execute.

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
  def test_generates_filename_from_title
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "My Test Title")

    assert_match(/^\d{4}-\d{2}-\d{2}-my-test-title$/, filename)
  end

  def test_generates_filename_removes_special_characters
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "Title with (special) chars!")

    assert_match(/title-with-special-chars$/, filename)
  end

  def test_generates_filename_collapses_multiple_hyphens
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "Title   with   spaces")

    refute_match(/--/, filename)
  end

  def test_builds_episode_data
    processor = EpisodeProcessor.new
    data = processor.send(
      :build_episode_data,
      "Test Title",
      "Test Author",
      "Test Description",
      "test-guid"
    )

    assert_equal "Test Title", data["title"]
    assert_equal "Test Author", data["author"]
    assert_equal "Test Description", data["description"]
    assert_equal "test-guid", data["id"]
    assert_equal "test-guid", data["guid"]
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_episode_processor.rb
# Expected: LoadError
```

**Step 3: Create implementation**

Create `lib/episode_processor.rb`:

```ruby
require "time"
require "securerandom"
require_relative "text_processor"
require_relative "tts"
require_relative "gcs_uploader"
require_relative "episode_manifest"
require_relative "podcast_publisher"

# Processes episode publishing from markdown to published podcast episode
# This is the main orchestrator that coordinates all the publishing steps
class EpisodeProcessor
  # Process an episode from start to finish
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def process(title, author, description, markdown_content)
    puts "Starting episode processing: #{title}"

    # Step 1: Generate filename from title
    filename = generate_filename(title)

    # Step 2: Save markdown to GCS with frontmatter (for record keeping)
    save_markdown_to_gcs(filename, title, author, description, markdown_content)

    # Step 3: Process markdown to plain text
    text = TextProcessor.convert_to_plain_text(markdown_content)
    puts "Processed markdown: #{text.length} characters"

    # Step 4: Generate TTS audio
    tts = TTS.new
    audio_content = tts.synthesize(text, voice: ENV.fetch("TTS_VOICE", "en-GB-Chirp3-HD-Enceladus"))
    puts "Generated audio: #{audio_content.bytesize} bytes"

    # Step 5: Save MP3 locally (temporary)
    mp3_path = save_mp3_locally(filename, audio_content)
    puts "Saved MP3 to: #{mp3_path}"

    # Step 6: Publish to podcast feed
    publish_episode(mp3_path, title, author, description)

    # Step 7: Cleanup local file
    File.delete(mp3_path) if File.exist?(mp3_path)

    # Step 8: Cleanup staging file from GCS
    cleanup_staging_file(filename)

    puts "Episode published successfully: #{title}"
  end

  private

  # Generate filename from title: "My Title" -> "2025-10-28-my-title"
  def generate_filename(title)
    date = Time.now.strftime("%Y-%m-%d")
    slug = title.downcase
               .gsub(/[^\w\s-]/, "") # Remove special chars
               .gsub(/\s+/, "-")      # Spaces to hyphens
               .gsub(/-+/, "-")       # Collapse multiple hyphens
               .strip
    "#{date}-#{slug}"
  end

  # Save markdown file to GCS with frontmatter
  def save_markdown_to_gcs(filename, title, author, description, content)
    frontmatter = "---\ntitle: \"#{title}\"\nauthor: \"#{author}\"\ndescription: \"#{description}\"\n---\n\n"
    full_content = frontmatter + content

    gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
    gcs.upload_content(
      content: full_content,
      remote_path: "input/#{filename}.md"
    )
    puts "Saved markdown to GCS: input/#{filename}.md"
  end

  # Save MP3 to local output directory
  def save_mp3_locally(filename, audio_content)
    Dir.mkdir("output") unless Dir.exist?("output")
    path = File.join("output", "#{filename}.mp3")
    File.write(path, audio_content, mode: "wb")
    path
  end

  # Publish episode using existing PodcastPublisher
  def publish_episode(mp3_path, title, author, description)
    podcast_config = YAML.load_file("config/podcast.yml")
    gcs_uploader = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    metadata = {
      "title" => title,
      "author" => author,
      "description" => description
    }

    publisher.publish(mp3_path, metadata)
  end

  # Cleanup staging file from GCS after processing
  def cleanup_staging_file(filename)
    gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
    gcs.delete_file(remote_path: "staging/#{filename}.md")
    puts "Cleaned up staging file: staging/#{filename}.md"
  rescue StandardError => e
    puts "Warning: Failed to cleanup staging file: #{e.message}"
    # Don't fail the whole process if cleanup fails
  end

  # Build episode data hash
  def build_episode_data(title, author, description, guid)
    {
      "id" => guid,
      "title" => title,
      "description" => description,
      "author" => author,
      "guid" => guid
    }
  end
end
```

**Step 4: Add delete_file method to GCSUploader**

We need to add a delete method to GCSUploader for cleanup. Edit `lib/gcs_uploader.rb`:

```ruby
# Add this method to the GCSUploader class
# Delete a file from GCS
# @param remote_path [String] Path in bucket (e.g., "staging/file.md")
def delete_file(remote_path:)
  file = @bucket.file(remote_path)
  file.delete if file
end
```

**Step 5: Run tests**

```bash
ruby test/test_episode_processor.rb
# Should pass
```

**Step 6: Run all tests and rubocop**

```bash
rake test
rake rubocop
```

**Commit**:
```bash
git add lib/episode_processor.rb lib/gcs_uploader.rb test/test_episode_processor.rb
git commit -m "Add EpisodeProcessor for episode publishing logic"
```

---

#### Task 3.2: Create Worker Service (Test First)

**What**: Create the Worker Sinatra application that processes episodes.

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
    get "/"
    assert_equal 200, last_response.status
  end

  def test_health_check_returns_json
    get "/"
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
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

  # Success Tests (with mocked processor)

  def test_valid_request_returns_200
    mock_processor do
      post "/process", valid_task_payload, json_headers
      assert_equal 200, last_response.status
    end
  end

  def test_valid_request_returns_success_json
    mock_processor do
      post "/process", valid_task_payload, json_headers

      body = JSON.parse(last_response.body)
      assert_equal "success", body["status"]
      assert_equal "Episode processed successfully", body["message"]
    end
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

  def mock_processor
    # In real implementation, we'll mock the EpisodeProcessor
    # For now, this is a placeholder
    yield
  end
end
```

**Step 2: Run tests (should fail)**

```bash
ruby test/test_worker.rb
# Expected: LoadError
```

**Step 3: Create the worker app**

Create `worker.rb`:

```ruby
require "sinatra"
require "sinatra/json"
require "json"
require_relative "lib/gcs_uploader"
require_relative "lib/episode_processor"

# Configure Sinatra
set :port, ENV.fetch("PORT", 8080)
set :bind, "0.0.0.0"
set :show_exceptions, false

# Health check endpoint for Cloud Run
get "/" do
  json status: "ok", message: "Podcast Worker Service"
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
  markdown_content = download_from_gcs(gcs_path)

  # Step 5: Process episode
  processor = EpisodeProcessor.new
  processor.process(title, author, description, markdown_content)

  # Step 6: Return success
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

# Download markdown content from GCS
def download_from_gcs(gcs_path)
  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"))
  gcs.download_file(remote_path: gcs_path)
end
```

**Step 4: Add download_file method to GCSUploader**

Edit `lib/gcs_uploader.rb` to add a download method:

```ruby
# Add this method to the GCSUploader class
# Download a file from GCS
# @param remote_path [String] Path in bucket (e.g., "staging/file.md")
# @return [String] File contents
def download_file(remote_path:)
  file = @bucket.file(remote_path)
  raise "File not found: #{remote_path}" unless file

  file.download.read
end
```

**Step 5: Run tests**

```bash
ruby test/test_worker.rb
# Should pass
```

**Step 6: Run all tests and rubocop**

```bash
rake test
rake rubocop
```

**Commit**:
```bash
git add worker.rb lib/gcs_uploader.rb test/test_worker.rb
git commit -m "Add worker service for episode processing"
```

---

#### Task 3.3: Create Worker Dockerfile

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

Update `.dockerignore` to exclude api.rb from worker:
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

### Phase 4: Deployment

#### Task 4.1: Update Environment Variables

**What**: Add new required environment variables for both services.

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
API_SECRET_TOKEN=your-secret-token-here

# Cloud Tasks Configuration
CLOUD_TASKS_LOCATION=us-central1
CLOUD_TASKS_QUEUE=episode-processing

# Worker Service URL (set after worker is deployed)
WORKER_URL=https://podcast-worker-XXXXXXXX.run.app/process

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
git commit -m "Add environment variables for Cloud Tasks and services"
```

---

#### Task 4.2: Create Cloud Tasks Queue

**What**: Create the Cloud Tasks queue that connects the two services.

**Why**: We need a queue before we can deploy the services.

**What to do**:

1. **Enable Cloud Tasks API**:
   ```bash
   gcloud services enable cloudtasks.googleapis.com
   ```

2. **Create the queue**:
   ```bash
   gcloud tasks queues create episode-processing \
     --location=us-central1 \
     --max-attempts=3 \
     --max-retry-duration=1h
   ```

3. **Verify the queue was created**:
   ```bash
   gcloud tasks queues describe episode-processing --location=us-central1
   ```

   You should see output showing the queue configuration.

4. **Update .env with queue name** (if not already there):
   ```bash
   echo "CLOUD_TASKS_QUEUE=episode-processing" >> .env
   ```

**Testing**: Queue is ready to use after creation.

**Note**: This is a one-time setup. The queue persists across deployments.

**Commit** (if you made config changes):
```bash
git commit --allow-empty -m "Create Cloud Tasks queue for episode processing"
```

---

#### Task 4.3: Deploy Worker Service First

**What**: Deploy the worker service to Cloud Run.

**Why**: We need the worker URL before we can deploy the API (API needs to know where to send tasks).

**What to do**:

1. **Build and deploy worker**:
   ```bash
   gcloud run deploy podcast-worker \
     --source . \
     --dockerfile Dockerfile.worker \
     --project $GOOGLE_CLOUD_PROJECT \
     --region us-central1 \
     --platform managed \
     --allow-unauthenticated \
     --memory 2Gi \
     --timeout 600s \
     --max-instances 1 \
     --min-instances 0 \
     --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
     --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET"
   ```

2. **Get the worker URL**:
   ```bash
   gcloud run services describe podcast-worker \
     --region us-central1 \
     --format 'value(status.url)'
   ```

   Copy this URL!

3. **Add /process to the URL and save to .env**:
   ```bash
   # If URL is: https://podcast-worker-abc123.run.app
   # Set WORKER_URL to: https://podcast-worker-abc123.run.app/process
   echo "WORKER_URL=https://podcast-worker-XXXXXXXX.run.app/process" >> .env
   ```

4. **Test the worker health check**:
   ```bash
   curl https://YOUR_WORKER_URL.run.app/
   # Should return: {"status":"ok","message":"Podcast Worker Service"}
   ```

**Important Security Note**:
We're using `--allow-unauthenticated` for simplicity. Cloud Tasks will invoke this endpoint. In production, you might want to:
- Add authentication between API and Worker
- Use Cloud Tasks service account authentication
- Restrict access by IP or service account

For now, the simple approach works fine.

**Commit** (if you made .env changes - don't commit .env itself):
```bash
git commit --allow-empty -m "Deploy worker service to Cloud Run"
```

---

#### Task 4.4: Deploy API Service

**What**: Deploy the API service to Cloud Run.

**Why**: Now that we have the worker URL, we can deploy the API that sends tasks to it.

**What to do**:

1. **Source environment variables**:
   ```bash
   source .env
   ```

2. **Deploy API service**:
   ```bash
   gcloud run deploy podcast-api \
     --source . \
     --dockerfile Dockerfile.api \
     --project $GOOGLE_CLOUD_PROJECT \
     --region us-central1 \
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
     --set-env-vars "CLOUD_TASKS_LOCATION=us-central1" \
     --set-env-vars "CLOUD_TASKS_QUEUE=episode-processing"
   ```

3. **Get the API URL**:
   ```bash
   gcloud run services describe podcast-api \
     --region us-central1 \
     --format 'value(status.url)'
   ```

   Save this - it's your public API endpoint!

4. **Test the API health check**:
   ```bash
   curl https://YOUR_API_URL.run.app/
   # Should return: {"status":"ok","message":"Podcast Publishing API"}
   ```

5. **Test authentication**:
   ```bash
   curl -X POST https://YOUR_API_URL.run.app/publish
   # Should return 401: {"status":"error","message":"Unauthorized..."}
   ```

**Commit**:
```bash
git commit --allow-empty -m "Deploy API service to Cloud Run"
```

---

#### Task 4.5: End-to-End Testing

**What**: Test the complete flow from API to Worker to published episode.

**What to do**:

1. **Create a test markdown file**:
   ```bash
   cat > /tmp/test-episode.md << 'EOF'
   # Test Episode

   This is a test episode to verify the complete publishing pipeline.

   ## Section One

   The API should upload this to GCS staging, then enqueue a task.

   ## Section Two

   The worker should pick up the task, generate TTS audio, and publish to the RSS feed.
   EOF
   ```

2. **Submit the episode**:
   ```bash
   curl -X POST https://YOUR_API_URL.run.app/publish \
     -H "Authorization: Bearer $API_SECRET_TOKEN" \
     -F "title=Test Episode $(date +%s)" \
     -F "author=API Tester" \
     -F "description=Testing the complete publishing pipeline" \
     -F "content=@/tmp/test-episode.md"
   ```

   Should return immediately:
   ```json
   {"status":"success","message":"Episode submitted for processing"}
   ```

3. **Check API logs** (verify task was enqueued):
   ```bash
   gcloud run logs read podcast-api --region us-central1 --limit 20
   ```

   Look for: "Enqueued task for: Test Episode"

4. **Check worker logs** (verify processing):
   ```bash
   gcloud run logs read podcast-worker --region us-central1 --limit 50
   ```

   Look for:
   - "Processing episode: Test Episode"
   - "Processed markdown"
   - "Generated audio"
   - "Episode published successfully"

5. **Verify episode in RSS feed**:
   ```bash
   curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml | grep "Test Episode"
   ```

   Should show your episode in the XML.

6. **List episodes in GCS**:
   ```bash
   gsutil ls gs://$GOOGLE_CLOUD_BUCKET/episodes/
   gsutil ls gs://$GOOGLE_CLOUD_BUCKET/input/
   ```

   Should show the MP3 file and markdown file.

7. **Check Cloud Tasks queue**:
   ```bash
   gcloud tasks queues describe episode-processing --location=us-central1
   ```

   Should show tasks processed count.

**If anything fails**:

- Check API logs for upload or task creation errors
- Check worker logs for processing errors
- Verify WORKER_URL is correct in API service
- Verify service account has necessary permissions
- Check Cloud Tasks queue for failed tasks:
  ```bash
  gcloud tasks list --queue=episode-processing --location=us-central1
  ```

**Success Criteria**:
- ✅ API returns 200 immediately
- ✅ Task appears in Cloud Tasks
- ✅ Worker processes the episode
- ✅ MP3 file appears in GCS
- ✅ Episode appears in RSS feed
- ✅ All logs show success

**Commit**:
```bash
git commit --allow-empty -m "Complete end-to-end testing of publishing pipeline"
```

---

#### Task 4.6: Create Deployment Scripts

**What**: Create convenience scripts for redeployment.

**Files to create**:
- `bin/deploy-api`
- `bin/deploy-worker`
- `bin/deploy-all`

**What to do**:

Create `bin/deploy-api`:
```bash
#!/bin/bash
set -e

echo "Deploying API Service..."
source .env

gcloud run deploy podcast-api \
  --source . \
  --dockerfile Dockerfile.api \
  --project $GOOGLE_CLOUD_PROJECT \
  --region us-central1 \
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
  --set-env-vars "CLOUD_TASKS_LOCATION=us-central1" \
  --set-env-vars "CLOUD_TASKS_QUEUE=episode-processing"

echo "API Service deployed successfully!"
```

Create `bin/deploy-worker`:
```bash
#!/bin/bash
set -e

echo "Deploying Worker Service..."
source .env

gcloud run deploy podcast-worker \
  --source . \
  --dockerfile Dockerfile.worker \
  --project $GOOGLE_CLOUD_PROJECT \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --memory 2Gi \
  --timeout 600s \
  --max-instances 1 \
  --min-instances 0 \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
  --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET"

echo "Worker Service deployed successfully!"
```

Create `bin/deploy-all`:
```bash
#!/bin/bash
set -e

echo "================================"
echo "Deploying Podcast Services"
echo "================================"

# Deploy worker first (API needs worker URL)
./bin/deploy-worker

# Get worker URL
WORKER_URL=$(gcloud run services describe podcast-worker \
  --region us-central1 \
  --format 'value(status.url)')/process

echo ""
echo "Worker URL: $WORKER_URL"
echo ""

# Update .env with worker URL if needed
if ! grep -q "^WORKER_URL=" .env; then
  echo "WORKER_URL=$WORKER_URL" >> .env
fi

# Deploy API
./bin/deploy-api

# Get API URL
API_URL=$(gcloud run services describe podcast-api \
  --region us-central1 \
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
echo "  curl -X POST $API_URL/publish \\"
echo "    -H \"Authorization: Bearer \$API_SECRET_TOKEN\" \\"
echo "    -F \"title=Test\" \\"
echo "    -F \"author=Test\" \\"
echo "    -F \"description=Test\" \\"
echo "    -F \"content=@article.md\""
```

Make them executable:
```bash
chmod +x bin/deploy-api bin/deploy-worker bin/deploy-all
```

**Testing**:
```bash
./bin/deploy-all
```

**Commit**:
```bash
git add bin/
git commit -m "Add deployment scripts for services"
```

---

### Phase 5: Documentation

#### Task 5.1: Create API Documentation

**What**: Document how to use the API.

**Files to create**:
- `docs/API.md`

**What to do**:

Create `docs/API.md`:
```markdown
# Podcast Publishing API Documentation

## Overview

HTTP API for publishing podcast episodes. Submit episode metadata and markdown content via POST request, and the system automatically generates audio, uploads to cloud storage, and updates the RSS feed.

## Architecture

The system uses two Cloud Run services:

1. **API Service**: Accepts requests, validates input, uploads to GCS, enqueues tasks
2. **Worker Service**: Processes episodes (TTS, publish, RSS update)

Connected by **Google Cloud Tasks** for reliable async processing.

## Base URL

Production: `https://YOUR_API_SERVICE.run.app`
Local: `http://localhost:8080`

## Authentication

All requests require Bearer token authentication:

```http
Authorization: Bearer YOUR_SECRET_TOKEN
```

The token is set via the `API_SECRET_TOKEN` environment variable.

## Endpoints

### Health Check

```http
GET /
```

Returns API status.

**Response:**
```json
{
  "status": "ok",
  "message": "Podcast Publishing API"
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
curl -X POST https://YOUR_API_SERVICE.run.app/publish \
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
| 401 | `{"status":"error","message":"Unauthorized: Invalid or missing authentication token"}` | Invalid authentication |
| 500 | `{"status":"error","message":"Internal server error"}` | Server error |

## Processing Flow

After successful submission (200 response):

1. Episode markdown is uploaded to GCS staging area
2. Task is enqueued to Cloud Tasks
3. API returns success immediately (processing continues in background)
4. Worker service is triggered by Cloud Tasks
5. Worker downloads markdown from GCS
6. Text-to-speech audio is generated (30-60 seconds)
7. Audio file is uploaded to GCS
8. RSS feed is updated with new episode
9. Original markdown is saved to GCS input directory
10. Staging file is cleaned up

Total processing time: 30-90 seconds depending on article length.

## Monitoring

**View API logs:**
```bash
gcloud run logs read podcast-api --region us-central1 --limit 50
```

**View Worker logs:**
```bash
gcloud run logs read podcast-worker --region us-central1 --limit 50
```

**Check Cloud Tasks queue:**
```bash
gcloud tasks queues describe episode-processing --location=us-central1
```

**Check RSS feed:**
```bash
curl https://storage.googleapis.com/YOUR_BUCKET/feed.xml
```

## Error Handling

Processing errors are logged but not returned to the client (since processing is asynchronous).

Common errors and solutions:

| Error | Cause | Solution |
|-------|-------|----------|
| TTS rate limit exceeded | Too many requests | Wait and Cloud Tasks will retry automatically |
| Content filter triggered | Inappropriate content detected | Check worker logs, modify content |
| Upload failure | GCS permissions issue | Verify service account has Storage Admin role |
| Task enqueue failure | Cloud Tasks quota or config | Check Cloud Tasks queue exists and has capacity |

Cloud Tasks automatically retries failed tasks up to 3 times with exponential backoff.

## Local Development

Testing locally requires running both services:

**Terminal 1 - Worker:**
```bash
GOOGLE_CLOUD_PROJECT=your-project \
GOOGLE_CLOUD_BUCKET=your-bucket \
GOOGLE_APPLICATION_CREDENTIALS=./credentials.json \
ruby worker.rb
```

**Terminal 2 - API:**
```bash
API_SECRET_TOKEN=test123 \
GOOGLE_CLOUD_PROJECT=your-project \
GOOGLE_CLOUD_BUCKET=your-bucket \
GOOGLE_APPLICATION_CREDENTIALS=./credentials.json \
WORKER_URL=http://localhost:8080/process \
CLOUD_TASKS_LOCATION=us-central1 \
CLOUD_TASKS_QUEUE=episode-processing \
ruby api.rb
```

**Terminal 3 - Test:**
```bash
echo "# Test Article" > test.md
curl -X POST http://localhost:8080/publish \
  -H "Authorization: Bearer test123" \
  -F "title=Test" \
  -F "author=Test" \
  -F "description=Test" \
  -F "content=@test.md"
```

Note: Local testing still requires Cloud Tasks queue to exist in GCP.

## Cost Estimates

**Google Cloud Run:**
- Free tier: 2 million requests/month, 360,000 GB-seconds
- API service: ~$0-2/month (lightweight, fast requests)
- Worker service: ~$0-3/month (heavier, longer requests)
- Expected total: $0-5/month for personal use

**Google Cloud Tasks:**
- Free tier: 1 million tasks/month
- Expected cost: $0/month (well within free tier)

**Google Cloud TTS:**
- $16 per 1 million characters (WaveNet voices)
- Example: 10,000-character article = ~$0.16

**Google Cloud Storage:**
- $0.02 per GB/month
- Example: 100 episodes at 5MB each = $0.01/month

**Total estimated cost:** $1-10/month depending on usage

## Service URLs

After deployment, save these URLs:

```bash
# API Service
gcloud run services describe podcast-api \
  --region us-central1 \
  --format 'value(status.url)'

# Worker Service
gcloud run services describe podcast-worker \
  --region us-central1 \
  --format 'value(status.url)'
```

## Deployment

Deploy both services:
```bash
./bin/deploy-all
```

Deploy individual services:
```bash
./bin/deploy-api
./bin/deploy-worker
```

See deployment scripts in `bin/` directory.
```

**Commit**:
```bash
git add docs/API.md
git commit -m "Add comprehensive API documentation"
```

---

#### Task 5.2: Update README

**What**: Update the main README to document the API.

**Files to modify**:
- `README.md`

**What to do**:

Add after the "Usage" section in `README.md`:

```markdown
## API Usage

Publish episodes via HTTP API:

```bash
curl -X POST https://your-api-service.run.app/publish \
  -H "Authorization: Bearer YOUR_SECRET_TOKEN" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@path/to/article.md"
```

Returns immediately with `{"status":"success"}`. Processing happens in the background via Cloud Tasks.

See [API Documentation](docs/API.md) for full details.

### Architecture

- **API Service**: Fast endpoint that accepts requests and enqueues jobs
- **Worker Service**: Processes TTS generation and publishing
- **Cloud Tasks**: Reliable job queue connecting the services

### Deployment

Deploy both services to Google Cloud Run:

```bash
./bin/deploy-all
```

See [API Documentation](docs/API.md) for setup instructions.
```

**Commit**:
```bash
git add README.md
git commit -m "Update README with API usage and architecture"
```

---

## Summary

### What We Built

1. **Cloud Tasks Integration**: Task enqueuer for reliable async processing
2. **API Service**: Fast Sinatra app that validates and enqueues
3. **Worker Service**: Heavy-duty Sinatra app that processes episodes
4. **Episode Processor**: Orchestrates TTS, upload, and RSS generation
5. **Deployment Scripts**: Easy redeployment for both services
6. **Complete Documentation**: API docs and usage instructions

### Architecture

```
User → API (Cloud Run) → Cloud Tasks → Worker (Cloud Run) → [TTS, GCS, RSS] → Published Episode
```

### Key Files Created/Modified

- `lib/task_enqueuer.rb` - Cloud Tasks helper
- `lib/episode_processor.rb` - Episode processing orchestrator
- `lib/gcs_uploader.rb` - Added download and delete methods
- `api.rb` - API Sinatra service
- `worker.rb` - Worker Sinatra service
- `Dockerfile.api` - API container
- `Dockerfile.worker` - Worker container
- `bin/deploy-*` - Deployment scripts
- `docs/API.md` - API documentation
- Tests for all components

### Deployment URLs

After deployment, you'll have:
- API: `https://podcast-api-[hash].run.app`
- Worker: `https://podcast-worker-[hash].run.app`

### Usage

```bash
curl -X POST https://your-api.run.app/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=My Episode" \
  -F "author=Author" \
  -F "description=Description" \
  -F "content=@article.md"
```

### Costs

- **Cloud Run**: $0-5/month (free tier covers most personal use)
- **Cloud Tasks**: $0/month (free tier)
- **GCS + TTS**: $1-5/month depending on usage

**Total: ~$5/month for moderate usage**

### Testing Strategy

- **Unit tests**: Test all business logic and validation
- **Integration**: Manual e2e testing of full flow
- **TDD**: Write tests before implementation for all code
- **Cloud Logging**: Monitor processing in production

### Advantages Over Redis/Sidekiq

✅ **No Redis** - One less service to manage
✅ **Fully serverless** - Everything scales to zero
✅ **Reliable** - Cloud Tasks handles retries automatically
✅ **Simpler** - All within Google Cloud ecosystem
✅ **Cost effective** - Free tier covers personal use
✅ **Monitoring** - Built-in logging and metrics

---

## Troubleshooting Guide

### Common Issues

**Issue: "Task enqueue failed"**
- Solution: Verify Cloud Tasks queue exists
- Check: `gcloud tasks queues describe episode-processing --location=us-central1`
- Create if missing: `gcloud tasks queues create episode-processing --location=us-central1`

**Issue: "Worker not receiving tasks"**
- Solution: Check WORKER_URL in API service environment
- Verify: `gcloud run services describe podcast-api --region us-central1`
- Update if wrong: Redeploy API with correct WORKER_URL

**Issue: "401 Unauthorized" when testing API**
- Solution: Check API_SECRET_TOKEN matches in .env and request

**Issue: "Episode not appearing in RSS feed"**
- Check worker logs: `gcloud run logs read podcast-worker --region us-central1`
- Verify GCS bucket permissions
- Check Cloud Tasks for failed tasks

**Issue: "TTS API quota exceeded"**
- Wait for quota reset (resets daily)
- Cloud Tasks will automatically retry
- Check quota: https://console.cloud.google.com/iam-admin/quotas

**Issue: "Docker build fails"**
- Check Dockerfile syntax
- Ensure Gemfile.lock is committed
- Try: `docker system prune -a` and rebuild

**Issue: "Cloud Run deployment fails"**
- Check gcloud authentication: `gcloud auth list`
- Verify project: `gcloud config get-value project`
- Check billing is enabled
- Review error in deployment output

### Viewing Logs

**API logs:**
```bash
gcloud run logs read podcast-api --region us-central1 --limit 50
```

**Worker logs:**
```bash
gcloud run logs read podcast-worker --region us-central1 --limit 50
```

**Cloud Tasks status:**
```bash
gcloud tasks queues describe episode-processing --location=us-central1
```

**List pending/failed tasks:**
```bash
gcloud tasks list --queue=episode-processing --location=us-central1
```

### Testing Individual Components

**Test API health:**
```bash
curl https://YOUR_API_URL.run.app/
```

**Test Worker health:**
```bash
curl https://YOUR_WORKER_URL.run.app/
```

**Test authentication:**
```bash
curl -X POST https://YOUR_API_URL.run.app/publish
# Should return 401
```

**Test GCS access:**
```bash
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/
```

---

## Next Steps (Future Enhancements)

Not in scope for this plan, but potential improvements:

1. **Task status endpoint**: Check if a submitted episode has been processed
2. **Webhook notifications**: Notify when processing completes/fails
3. **Episode management**: List, update, delete episodes
4. **Multiple voices**: Support different voices per episode
5. **Scheduled publishing**: Specify publish time in future
6. **Retry UI**: Manually retry failed tasks
7. **Email publishing**: Send articles via email
8. **Web UI**: Simple form interface instead of cURL

---

## Principles Followed

- **DRY**: Reused existing components (TextProcessor, TTS, PodcastPublisher)
- **YAGNI**: Built only what's needed, no premature features
- **TDD**: Wrote tests before implementation for all code
- **Frequent commits**: Each task = one commit
- **Separation of concerns**: API, worker, and processing logic separate
- **12-factor app**: Config via environment, stateless processes
- **Serverless first**: Everything scales to zero, no always-on services
- **Fail fast**: Validation at API layer, detailed error logging
- **Reliable**: Cloud Tasks handles retries automatically

---

End of implementation plan.
