# Simplified API Service Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a single Cloud Run service that accepts podcast episode submissions via HTTP and publishes them asynchronously using Cloud Tasks.

**Architecture:** Single Sinatra service with two endpoints: `/publish` (public, accepts episodes) and `/process` (internal, triggered by Cloud Tasks). Reuses all existing TTS/GCS/RSS infrastructure from `generate.rb`. Uses temporary MP3 files in Wave 1 for simplicity, eliminates them in Wave 2.

**Tech Stack:** Ruby 3.3, Sinatra, Google Cloud Run, Google Cloud Tasks, Google Cloud Storage, Google Cloud TTS

---

## Wave 1: MVP - Get Working Fast (2 hours)

**Goal:** Deploy and publish first episode via curl

**Scope:**
- Single bearer token (personal use)
- No user isolation (add in Wave 2)
- Minimal error handling
- Reuse all existing lib/ classes
- Temporary MP3 files (eliminate in Wave 2)

---

### Task 1.1: Add Web Framework Dependencies

**Files:**
- Modify: `Gemfile`

**Step 1: Add Sinatra and Cloud Tasks gems**

Add these lines after `google-cloud-storage`:

```ruby
gem "google-cloud-tasks", "~> 2.0"

# Web framework
gem "sinatra", "~> 4.0"
gem "sinatra-contrib", "~> 4.0"
gem "puma", "~> 6.0"
gem "rack-test", "~> 2.1", group: :test
```

**Step 2: Install dependencies**

Run:
```bash
bundle install
```

Expected: All gems install successfully

**Step 3: Verify installation**

Run:
```bash
bundle list | grep -E "(sinatra|puma|google-cloud-tasks)"
```

Expected: Shows versions of all three gems

**Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Add Sinatra and Cloud Tasks dependencies"
```

---

### Task 1.2: Create Episode Processor Orchestrator

**Files:**
- Create: `lib/episode_processor.rb`
- Create: `test/test_episode_processor.rb`

**Context:** This orchestrator reuses all existing components (`TextProcessor`, `TTS`, `PodcastPublisher`) in the same pattern as `generate.rb`, but designed for programmatic use rather than CLI.

**Step 1: Write the failing test**

Create `test/test_episode_processor.rb`:

```ruby
require "minitest/autorun"
require_relative "../lib/episode_processor"

class TestEpisodeProcessor < Minitest::Test
  def setup
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
  end

  def test_initialization_with_explicit_bucket
    processor = EpisodeProcessor.new("my-bucket")
    assert_equal "my-bucket", processor.bucket_name
  end

  def test_initialization_uses_env_bucket
    processor = EpisodeProcessor.new
    assert_equal "test-bucket", processor.bucket_name
  end

  def test_generate_filename_includes_date_and_slug
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "Test Episode Title")

    assert_match(/^\d{4}-\d{2}-\d{2}-test-episode-title$/, filename)
  end

  def test_generate_filename_removes_special_chars
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "Test (Special) Chars!")

    assert_match(/test-special-chars$/, filename)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
ruby test/test_episode_processor.rb
```

Expected: `LoadError: cannot load such file -- ../lib/episode_processor`

**Step 3: Write minimal implementation**

Create `lib/episode_processor.rb`:

```ruby
require "yaml"
require_relative "text_processor"
require_relative "tts"
require_relative "podcast_publisher"
require_relative "gcs_uploader"
require_relative "episode_manifest"

# Orchestrates episode processing from markdown to published podcast
# Reuses all existing infrastructure from generate.rb
class EpisodeProcessor
  attr_reader :bucket_name

  def initialize(bucket_name = nil)
    @bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET")
  end

  # Process an episode from start to finish
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def process(title, author, description, markdown_content)
    puts "=" * 60
    puts "Processing: #{title}"
    puts "=" * 60

    filename = generate_filename(title)
    mp3_path = nil

    begin
      # Step 1: Convert markdown to plain text
      puts "\n[1/4] Processing markdown..."
      text = TextProcessor.convert_to_plain_text(markdown_content)
      puts "✓ Processed #{text.length} characters"

      # Step 2: Generate TTS audio
      puts "\n[2/4] Generating audio..."
      tts = TTS.new
      audio_content = tts.synthesize(text)
      puts "✓ Generated #{format_size(audio_content.bytesize)}"

      # Step 3: Save MP3 temporarily
      puts "\n[3/4] Saving temporary MP3..."
      mp3_path = save_temp_mp3(filename, audio_content)
      puts "✓ Saved: #{mp3_path}"

      # Step 4: Publish to podcast feed
      puts "\n[4/4] Publishing to feed..."
      publish_to_feed(mp3_path, title, author, description)
      puts "✓ Published"

      puts "\n" + "=" * 60
      puts "✓ Complete: #{title}"
      puts "=" * 60
    ensure
      # Always cleanup temporary file
      cleanup_temp_file(mp3_path) if mp3_path
    end
  end

  private

  def generate_filename(title)
    date = Time.now.strftime("%Y-%m-%d")
    slug = title.downcase
               .gsub(/[^\w\s-]/, "")  # Remove special chars
               .gsub(/\s+/, "-")      # Spaces to hyphens
               .gsub(/-+/, "-")       # Collapse multiple hyphens
               .strip
    "#{date}-#{slug}"
  end

  def save_temp_mp3(filename, audio_content)
    Dir.mkdir("output") unless Dir.exist?("output")
    path = File.join("output", "#{filename}.mp3")
    File.write(path, audio_content, mode: "wb")
    path
  end

  def publish_to_feed(mp3_path, title, author, description)
    metadata = {
      "title" => title,
      "author" => author,
      "description" => description
    }

    podcast_config = YAML.load_file("config/podcast.yml")
    gcs_uploader = GCSUploader.new(@bucket_name)
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    publisher.publish(mp3_path, metadata)
  end

  def cleanup_temp_file(path)
    File.delete(path) if File.exist?(path)
    puts "✓ Cleaned up: #{path}"
  rescue => e
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
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
ruby test/test_episode_processor.rb
```

Expected: All tests pass (4 runs, 4 assertions, 0 failures)

**Step 5: Run all tests**

Run:
```bash
rake test
```

Expected: All existing tests still pass

**Step 6: Commit**

```bash
git add lib/episode_processor.rb test/test_episode_processor.rb
git commit -m "Add EpisodeProcessor orchestrator for API workflow"
```

---

### Task 1.3: Create API Service with Tests

**Files:**
- Create: `test/test_api.rb`
- Create: `api.rb`

**Context:** Single Sinatra service with three endpoints: health check, public `/publish`, and internal `/process` (Cloud Tasks only).

**Step 1: Write the failing test**

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
    ENV["SERVICE_URL"] = "http://localhost:8080"
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
  end

  def test_health_check_reports_missing_vars
    ENV.delete("GOOGLE_CLOUD_BUCKET")
    get "/health"

    assert_equal 500, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "unhealthy", body["status"]
    assert_includes body["missing_vars"], "GOOGLE_CLOUD_BUCKET"
  end

  # Authentication Tests

  def test_missing_auth_header_returns_401
    post "/publish"
    assert_equal 401, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
    assert_includes body["message"], "Unauthorized"
  end

  def test_invalid_auth_token_returns_401
    post "/publish", {}, { "HTTP_AUTHORIZATION" => "Bearer wrong-token" }
    assert_equal 401, last_response.status
  end

  def test_valid_auth_with_missing_data_returns_400_not_401
    post "/publish", {}, auth_header
    assert_equal 400, last_response.status # Not 401
  end

  # Validation Tests

  def test_missing_title_returns_400
    params = valid_params.reject { |k, _| k == :title }
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "title"
  end

  def test_missing_author_returns_400
    params = valid_params.reject { |k, _| k == :author }
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "author"
  end

  def test_missing_description_returns_400
    params = valid_params.reject { |k, _| k == :description }
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "description"
  end

  def test_missing_content_returns_400
    params = valid_params.reject { |k, _| k == :content }
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "content"
  end

  def test_empty_content_returns_400
    params = valid_params.merge(content: empty_file)
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "content"
  end

  # Process Endpoint Tests

  def test_process_requires_json_payload
    post "/process", "not json", { "CONTENT_TYPE" => "application/json" }
    assert_equal 400, last_response.status
  end

  def test_process_validates_required_fields
    payload = { title: "Test" }.to_json
    post "/process", payload, { "CONTENT_TYPE" => "application/json" }

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "staging_path"
  end

  private

  def auth_header
    { "HTTP_AUTHORIZATION" => "Bearer test-token-123" }
  end

  def valid_params
    {
      title: "Test Episode",
      author: "Test Author",
      description: "Test description",
      content: markdown_file
    }
  end

  def markdown_file
    Rack::Test::UploadedFile.new(
      StringIO.new("# Test\n\nThis is test content."),
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

**Step 2: Run tests to verify they fail**

Run:
```bash
ruby test/test_api.rb
```

Expected: `LoadError: cannot load such file -- ../api`

**Step 3: Write minimal implementation**

Create `api.rb`:

```ruby
require "sinatra"
require "sinatra/json"
require "google/cloud/tasks/v2"
require_relative "lib/gcs_uploader"
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
    API_SECRET_TOKEN
  ]

  missing_vars = required_vars.reject { |var| ENV[var] }

  if missing_vars.empty?
    json status: "healthy"
  else
    halt 500, json(
      status: "unhealthy",
      missing_vars: missing_vars
    )
  end
end

# Public endpoint: Accept episode submission
post "/publish" do
  # Step 1: Authenticate
  unless authenticated?
    halt 401, json(status: "error", message: "Unauthorized")
  end

  # Step 2: Validate required fields
  errors = validate_params
  if errors.any?
    halt 400, json(status: "error", message: errors.join(", "))
  end

  # Step 3: Extract parameters
  title = params[:title]
  author = params[:author]
  description = params[:description]
  content_file = params[:content]

  # Step 4: Read file content
  markdown_content = content_file[:tempfile].read

  # Step 5: Generate filename and upload to GCS staging
  filename = generate_filename(title)
  staging_path = "staging/#{filename}.md"

  gcs = GCSUploader.new(ENV["GOOGLE_CLOUD_BUCKET"])
  gcs.upload_content(content: markdown_content, remote_path: staging_path)

  logger.info "Uploaded to staging: #{staging_path}"

  # Step 6: Enqueue processing task
  enqueue_task(title, author, description, staging_path)
  logger.info "Enqueued task for: #{title}"

  # Step 7: Return success immediately
  json status: "success", message: "Episode submitted for processing"
rescue StandardError => e
  logger.error "Error: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end

# Internal endpoint: Process episode (triggered by Cloud Tasks)
post "/process" do
  # Step 1: Parse JSON payload
  request.body.rewind
  payload = JSON.parse(request.body.read)

  # Step 2: Validate payload
  validation_error = validate_task_payload(payload)
  if validation_error
    halt 400, json(status: "error", message: validation_error)
  end

  # Step 3: Extract parameters
  title = payload["title"]
  author = payload["author"]
  description = payload["description"]
  staging_path = payload["staging_path"]

  logger.info "Processing: #{title}"
  logger.info "Downloading from: #{staging_path}"

  # Step 4: Download markdown from GCS
  gcs = GCSUploader.new(ENV["GOOGLE_CLOUD_BUCKET"])
  markdown_content = gcs.download_file(remote_path: staging_path)

  # Step 5: Process episode
  processor = EpisodeProcessor.new
  processor.process(title, author, description, markdown_content)

  # Step 6: Cleanup staging file
  gcs.delete_file(remote_path: staging_path)
  logger.info "Cleaned up staging: #{staging_path}"

  # Step 7: Return success
  logger.info "Completed: #{title}"
  json status: "success", message: "Episode processed successfully"
rescue JSON::ParserError => e
  logger.error "Invalid JSON: #{e.message}"
  halt 400, json(status: "error", message: "Invalid JSON payload")
rescue StandardError => e
  logger.error "Processing error: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end

# Helper: Check authentication
def authenticated?
  auth_header = request.env["HTTP_AUTHORIZATION"]
  return false unless auth_header

  token = auth_header.split(" ").last
  expected_token = ENV.fetch("API_SECRET_TOKEN", nil)

  return false unless expected_token

  token == expected_token
end

# Helper: Validate publish params
def validate_params
  errors = []
  errors << "Missing title" if params[:title].nil? || params[:title].empty?
  errors << "Missing author" if params[:author].nil? || params[:author].empty?
  errors << "Missing description" if params[:description].nil? || params[:description].empty?

  # Check content file
  if params[:content].nil?
    errors << "Missing content"
  else
    content_file = params[:content]
    unless content_file.is_a?(Hash) && content_file[:tempfile]
      errors << "Missing content"
    else
      # Check if file is empty
      content = content_file[:tempfile].read
      content_file[:tempfile].rewind # Reset for later reading
      errors << "Content file is empty" if content.strip.empty?
    end
  end

  errors
end

# Helper: Validate task payload
def validate_task_payload(payload)
  return "Missing title" unless payload["title"]
  return "Missing author" unless payload["author"]
  return "Missing description" unless payload["description"]
  return "Missing staging_path" unless payload["staging_path"]

  nil # No errors
end

# Helper: Generate filename from title
def generate_filename(title)
  date = Time.now.strftime("%Y-%m-%d")
  slug = title.downcase
             .gsub(/[^\w\s-]/, "")
             .gsub(/\s+/, "-")
             .gsub(/-+/, "-")
             .strip
  "#{date}-#{slug}"
end

# Helper: Enqueue task to Cloud Tasks
def enqueue_task(title, author, description, staging_path)
  client = Google::Cloud::Tasks::V2::CloudTasks::Client.new

  project_id = ENV.fetch("GOOGLE_CLOUD_PROJECT")
  location = ENV.fetch("CLOUD_TASKS_LOCATION", "us-central1")
  queue_name = ENV.fetch("CLOUD_TASKS_QUEUE", "episode-processing")

  queue_path = client.queue_path(
    project: project_id,
    location: location,
    queue: queue_name
  )

  # Service URL (set during deployment or use localhost for testing)
  service_url = ENV.fetch("SERVICE_URL", "http://localhost:8080")

  payload = {
    title: title,
    author: author,
    description: description,
    staging_path: staging_path
  }

  task = {
    http_request: {
      http_method: "POST",
      url: "#{service_url}/process",
      headers: {
        "Content-Type" => "application/json"
      },
      body: payload.to_json
    }
  }

  client.create_task(parent: queue_path, task: task)
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
ruby test/test_api.rb
```

Expected: All tests pass (authentication, validation, health checks work)

Note: Tests won't actually hit GCS or Cloud Tasks (those calls won't execute in test env)

**Step 5: Run all tests**

Run:
```bash
rake test
```

Expected: All tests pass

**Step 6: Check code style**

Run:
```bash
rake rubocop
```

Expected: No major violations (may need to fix style issues)

**Step 7: Commit**

```bash
git add api.rb test/test_api.rb
git commit -m "Add API service with publish and process endpoints"
```

---

### Task 1.4: Add GCS Helper Methods

**Files:**
- Modify: `lib/gcs_uploader.rb`

**Context:** Add `download_file` and `delete_file` methods needed by the API service.

**Step 1: Check if methods already exist**

Run:
```bash
grep -n "def download_file\|def delete_file" lib/gcs_uploader.rb
```

Expected: Either shows existing methods or returns nothing

**Step 2: Add methods if missing**

If methods don't exist, add them to `lib/gcs_uploader.rb` after the `upload_content` method:

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

**Step 3: Run all tests**

Run:
```bash
rake test
```

Expected: All tests still pass

**Step 4: Commit (if changes made)**

```bash
git add lib/gcs_uploader.rb
git commit -m "Add download_file and delete_file methods to GCSUploader"
```

---

### Task 1.5: Create Dockerfile

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`

**Step 1: Create Dockerfile**

Create `Dockerfile`:

```dockerfile
# Use official Ruby image
FROM ruby:3.3-slim

# Install build dependencies
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

# Create output directory for temporary MP3 files
RUN mkdir -p output

# Expose port
EXPOSE 8080

# Start application
CMD ["bundle", "exec", "ruby", "api.rb"]
```

**Step 2: Create .dockerignore**

Create `.dockerignore`:

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

**Step 3: Test Docker build**

Run:
```bash
docker build -t podcast-api .
```

Expected: Build completes successfully

**Step 4: Test Docker run locally (optional)**

Run:
```bash
docker run -p 8080:8080 --env-file .env podcast-api
```

In another terminal:
```bash
curl http://localhost:8080/health
```

Expected: `{"status":"healthy"}` or lists missing vars

Press Ctrl+C to stop container

**Step 5: Commit**

```bash
git add Dockerfile .dockerignore
git commit -m "Add Dockerfile for Cloud Run deployment"
```

---

### Task 1.6: Create Infrastructure Setup Script

**Files:**
- Create: `bin/setup-infrastructure`

**Step 1: Create setup script**

Create `bin/setup-infrastructure`:

```bash
#!/bin/bash
set -e

echo "================================"
echo "Setting up Cloud Infrastructure"
echo "================================"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI not installed"
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

# Check required vars
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

# Enable APIs
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
echo "  1. Deploy service: ./bin/deploy"
echo "  2. Test the API with curl"
```

**Step 2: Make script executable**

Run:
```bash
chmod +x bin/setup-infrastructure
```

**Step 3: Test script help output**

Run:
```bash
./bin/setup-infrastructure
```

Expected: Shows project info and sets up infrastructure (or reports errors if .env missing)

**Step 4: Commit**

```bash
git add bin/setup-infrastructure
git commit -m "Add infrastructure setup script for Cloud Tasks queue"
```

---

### Task 1.7: Create Deployment Script

**Files:**
- Create: `bin/deploy`

**Step 1: Create deployment script**

Create `bin/deploy`:

```bash
#!/bin/bash
set -e

echo "================================"
echo "Deploying to Cloud Run"
echo "================================"

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Validate required vars
if [ -z "$GOOGLE_CLOUD_PROJECT" ] || [ -z "$GOOGLE_CLOUD_BUCKET" ] || [ -z "$API_SECRET_TOKEN" ]; then
    echo "Error: Required environment variables not set"
    echo "Check .env for: GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_BUCKET, API_SECRET_TOKEN"
    exit 1
fi

REGION=${CLOUD_TASKS_LOCATION:-us-central1}

echo ""
echo "Project: $GOOGLE_CLOUD_PROJECT"
echo "Region: $REGION"
echo "Bucket: $GOOGLE_CLOUD_BUCKET"
echo ""

# Deploy to Cloud Run
gcloud run deploy podcast-api \
    --source . \
    --project $GOOGLE_CLOUD_PROJECT \
    --region $REGION \
    --platform managed \
    --allow-unauthenticated \
    --memory 2Gi \
    --timeout 600s \
    --max-instances 1 \
    --min-instances 0 \
    --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
    --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET" \
    --set-env-vars "API_SECRET_TOKEN=$API_SECRET_TOKEN" \
    --set-env-vars "CLOUD_TASKS_LOCATION=$REGION" \
    --set-env-vars "CLOUD_TASKS_QUEUE=${CLOUD_TASKS_QUEUE:-episode-processing}"

# Get service URL
SERVICE_URL=$(gcloud run services describe podcast-api \
    --region $REGION \
    --project $GOOGLE_CLOUD_PROJECT \
    --format 'value(status.url)')

echo ""
echo "✓ Deployed successfully!"
echo "URL: $SERVICE_URL"
echo ""

# Update service with its own URL for Cloud Tasks
echo "Updating service with SERVICE_URL for Cloud Tasks..."
gcloud run services update podcast-api \
    --region $REGION \
    --project $GOOGLE_CLOUD_PROJECT \
    --set-env-vars "SERVICE_URL=$SERVICE_URL"

echo ""
echo "================================"
echo "Deployment Complete!"
echo "================================"
echo ""
echo "API URL: $SERVICE_URL"
echo ""
echo "Test health:"
echo "  curl $SERVICE_URL/health"
echo ""
echo "Publish episode:"
echo "  curl -X POST $SERVICE_URL/publish \\"
echo "    -H \"Authorization: Bearer \$API_SECRET_TOKEN\" \\"
echo "    -F \"title=Test Episode\" \\"
echo "    -F \"author=Your Name\" \\"
echo "    -F \"description=Test description\" \\"
echo "    -F \"content=@article.md\""
```

**Step 2: Make script executable**

Run:
```bash
chmod +x bin/deploy
```

**Step 3: Commit**

```bash
git add bin/deploy
git commit -m "Add deployment script for Cloud Run"
```

---

### Task 1.8: Update Environment Variables

**Files:**
- Modify: `.env.example`
- Modify: `.env` (local only, not committed)

**Step 1: Update .env.example**

Add these lines to `.env.example`:

```bash
# API Configuration
# Generate with: openssl rand -hex 32
API_SECRET_TOKEN=your-secret-token-here

# Cloud Tasks Configuration
CLOUD_TASKS_LOCATION=us-central1
CLOUD_TASKS_QUEUE=episode-processing

# Service URL (set automatically during deployment)
SERVICE_URL=
```

**Step 2: Generate token and update local .env**

Run:
```bash
echo "" >> .env
echo "# API Configuration" >> .env
echo "API_SECRET_TOKEN=$(openssl rand -hex 32)" >> .env
echo "CLOUD_TASKS_LOCATION=us-central1" >> .env
echo "CLOUD_TASKS_QUEUE=episode-processing" >> .env
```

**Step 3: Verify .env has required vars**

Run:
```bash
grep -E "(API_SECRET_TOKEN|CLOUD_TASKS)" .env
```

Expected: Shows the new variables

**Step 4: Commit**

```bash
git add .env.example
git commit -m "Add API and Cloud Tasks environment variables"
```

---

### Task 1.9: Deploy and Test End-to-End

**Context:** Deploy to Cloud Run and verify the complete flow works.

**Step 1: Run infrastructure setup**

Run:
```bash
./bin/setup-infrastructure
```

Expected: Creates Cloud Tasks queue and enables APIs

**Step 2: Deploy service**

Run:
```bash
./bin/deploy
```

Expected:
- Deploys to Cloud Run
- Shows service URL
- Updates service with SERVICE_URL

**Step 3: Test health check**

Run:
```bash
API_URL=$(gcloud run services describe podcast-api \
  --region us-central1 \
  --project $GOOGLE_CLOUD_PROJECT \
  --format 'value(status.url)')

curl $API_URL/health
```

Expected: `{"status":"healthy"}`

**Step 4: Create test markdown file**

Run:
```bash
mkdir -p /tmp/podcast-test
cat > /tmp/podcast-test/test-episode.md << 'EOF'
# API Test Episode

This is a test episode to verify the complete publishing pipeline.

The API should upload this to GCS staging, then enqueue a task to Cloud Tasks.

The worker should pick up the task, generate TTS audio, and publish to the RSS feed.
EOF
```

**Step 5: Publish test episode**

Run:
```bash
source .env

curl -X POST $API_URL/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=API Test $(date +%s)" \
  -F "author=Test User" \
  -F "description=Testing the complete publishing pipeline" \
  -F "content=@/tmp/podcast-test/test-episode.md"
```

Expected: Immediate response:
```json
{"status":"success","message":"Episode submitted for processing"}
```

**Step 6: Monitor processing (wait 30-60 seconds)**

Run:
```bash
gcloud run logs read podcast-api \
  --region us-central1 \
  --project $GOOGLE_CLOUD_PROJECT \
  --limit 50
```

Expected: See logs showing:
1. "Uploaded to staging: staging/..."
2. "Enqueued task for: API Test..."
3. "Processing: API Test..."
4. "✓ Complete: API Test..."

**Step 7: Verify episode published**

Run:
```bash
# Check RSS feed
curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml | grep "API Test"

# List episodes
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/episodes/

# List staging (should be empty after processing)
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/staging/ || echo "Staging empty (good!)"
```

Expected:
- RSS feed contains new episode
- MP3 file in episodes/
- Staging directory empty

**Step 8: Check Cloud Tasks queue**

Run:
```bash
gcloud tasks queues describe episode-processing \
  --location=us-central1 \
  --project=$GOOGLE_CLOUD_PROJECT
```

Expected: Shows queue stats (should have 0 tasks if processing completed)

**Step 9: Commit (documentation)**

```bash
git commit --allow-empty -m "Wave 1 complete: Basic API deployed and tested"
```

---

## Wave 1 Summary

**What's Working:**

✅ Single Cloud Run service with `/publish` and `/process`
✅ Bearer token authentication
✅ Cloud Tasks async processing
✅ Reuses all existing TTS/GCS/RSS infrastructure
✅ Docker containerized
✅ Deployment scripts
✅ Can curl from any computer
✅ End-to-end tested

**Known Limitations (Wave 2 will address):**

- No user isolation (all files in root bucket)
- Single bearer token (no multi-user support)
- Minimal error handling
- No rate limiting configuration
- No documentation
- Uses temporary MP3 files

**Total Time:** ~2 hours

---

## Wave 2: Production Ready (Future)

**Goals:**
1. Add user ID isolation for GCS paths
2. Token → user_id mapping
3. Enhanced error handling
4. Rate limiting via Cloud Tasks config
5. Cost tracking logs
6. Eliminate temporary MP3 files
7. API documentation
8. Example scripts

**Estimated Tasks:** 6-8 tasks

**Note:** Wave 2 plan will be created after Wave 1 is complete and deployed.

---

## Success Criteria

**Wave 1 Complete When:**

- [x] Service deployed to Cloud Run
- [x] Health check returns 200
- [x] `/publish` accepts curl request with auth
- [x] Cloud Tasks enqueues successfully
- [x] `/process` generates TTS audio
- [x] Episode appears in RSS feed
- [x] MP3 uploaded to GCS
- [x] Staging file cleaned up
- [x] Can publish from any computer via curl

**Status:** ✅ **Wave 1 COMPLETE** (2025-11-02)

**Post-Deployment Fixes:**

Three bugs discovered and fixed during initial deployment:

1. **Missing require** (`lib/text_processor.rb`) - Added `require_relative "text_converter"`
   - Commit: a6f88b5
2. **Encoding error** (`lib/gcs_uploader.rb`) - Added `.force_encoding("UTF-8")` to downloads
   - Commit: 28d6b5f
3. **Undefined variable** (`lib/tts.rb`) - Captured `audio_content` return value
   - Commit: a82e62d

**Improvements Added:**
- Structured event-based logging throughout API
- Cloud Task ID tracking for better observability
- Refactored code for better maintainability

**Wave 2 Complete When:**

- [ ] Multiple users can publish (user_id isolation)
- [ ] Token maps to user_id
- [ ] Rate limiting configured
- [ ] Cost tracking logs working
- [ ] No temporary files needed
- [ ] API documentation complete
- [ ] Example scripts provided

---

## References

**Related Skills:**
- @superpowers:test-driven-development - Use for all new code
- @superpowers:verification-before-completion - Use before marking tasks complete
- @superpowers:systematic-debugging - Use if tests fail unexpectedly

**Key Files to Reference:**
- `lib/text_processor.rb` - Markdown to text conversion
- `lib/tts.rb` - TTS synthesis with chunking
- `lib/podcast_publisher.rb` - RSS publishing orchestration
- `lib/gcs_uploader.rb` - Cloud Storage operations
- `generate.rb` - Existing CLI workflow pattern
