# Implementation Plan: Podcast Publishing API

## Overview

This plan details how to build a minimal HTTP API that accepts podcast episode submissions via cURL and publishes them to the podcast feed. The API will be deployed to Google Cloud Run as a containerized Sinatra application.

### What We're Building

A single POST endpoint that:
1. Accepts authentication via Bearer token
2. Receives episode metadata (title, author, description) and markdown content file
3. Processes the episode asynchronously in a background job
4. Returns immediate success/error response
5. Logs processing results to Google Cloud Logging

### User Flow

```bash
curl -X POST https://your-podcast-api.run.app/publish \
  -H "Authorization: Bearer secret123" \
  -F "title=The Programmer Identity Crisis" \
  -F "author=Unknown" \
  -F "description=A reflection on AI and programming" \
  -F "content=@article.md"

# Response:
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
┌─────────────────────┐
│  Sinatra Web App    │
│  (Google Cloud Run) │
├─────────────────────┤
│ 1. Auth Check       │
│ 2. Validate Input   │
│ 3. Queue Job        │
│ 4. Return Response  │
└──────┬──────────────┘
       │
       │ Background Job
       ▼
┌─────────────────────┐
│  Publishing Worker  │
├─────────────────────┤
│ 1. Process Markdown │
│ 2. Generate TTS     │
│ 3. Upload to GCS    │
│ 4. Update RSS Feed  │
│ 5. Log Results      │
└─────────────────────┘
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

**Async Job Processing**: Understanding why we need background jobs
- Problem: TTS generation can take 30-60 seconds for long articles
- Solution: Accept request immediately, process in background, log results

### Tools Setup

1. **Install Docker Desktop**: https://www.docker.com/products/docker-desktop/
   - Required for local testing and Cloud Run deployment
   - Verify: `docker --version`

2. **Install Google Cloud SDK**: https://cloud.google.com/sdk/docs/install
   - Required for Cloud Run deployment
   - Verify: `gcloud --version`

3. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   gcloud auth configure-docker
   ```

4. **Install Redis** (for background jobs):
   ```bash
   # macOS
   brew install redis
   brew services start redis

   # Verify
   redis-cli ping  # Should return "PONG"
   ```

## Task Breakdown

### Phase 1: Background Job Infrastructure

#### Task 1.1: Add Sidekiq for Background Jobs

**What**: Add Sidekiq gem and configuration for async job processing.

**Why**: We need background processing so the API can return immediately while TTS generation (which takes 30-60 seconds) happens asynchronously.

**Files to modify**:
- `Gemfile`

**What to do**:

1. Add Sidekiq gems to `Gemfile`:
   ```ruby
   # Add after line 7
   gem "sidekiq"
   gem "sidekiq-cron" # For scheduled cleanup jobs if needed later
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Verify installation:
   ```bash
   bundle list | grep sidekiq
   # Should show: sidekiq (x.x.x)
   ```

**Testing**: No tests needed yet - just dependency installation.

**Commit**:
```bash
git add Gemfile Gemfile.lock
git commit -m "Add sidekiq for background job processing"
```

---

#### Task 1.2: Create Sidekiq Configuration

**What**: Configure Sidekiq with sensible defaults for our use case.

**Why**: Sidekiq needs configuration to connect to Redis and define job queues.

**Files to create**:
- `config/sidekiq.yml`

**What to do**:

1. Create `config/sidekiq.yml`:
   ```yaml
   # Sidekiq Configuration
   # Documentation: https://github.com/sidekiq/sidekiq/wiki/Advanced-Options

   # Development and production defaults
   :concurrency: 1  # Process one job at a time (TTS is CPU-intensive)
   :timeout: 600    # 10 minutes per job (long articles can take time)

   # Job queues (highest priority first)
   :queues:
     - critical  # For urgent jobs (future use)
     - default   # For standard episode publishing
     - low       # For cleanup tasks (future use)

   # Redis connection (uses REDIS_URL env var)
   # Format: redis://localhost:6379/0
   ```

2. Verify the file is valid YAML:
   ```bash
   ruby -ryaml -e "puts YAML.load_file('config/sidekiq.yml')"
   # Should output the config without errors
   ```

**Testing**: Configuration files don't need tests.

**Commit**:
```bash
git add config/sidekiq.yml
git commit -m "Add sidekiq configuration"
```

---

#### Task 1.3: Create Episode Publishing Worker (Test First)

**What**: Create a Sidekiq worker that processes episode publishing jobs.

**Why**: This worker encapsulates all the publishing logic (TTS, upload, RSS) in a background job.

**Files to create**:
- `test/test_episode_publisher_worker.rb` (create this FIRST)
- `lib/workers/episode_publisher_worker.rb` (create this AFTER tests)

**What to do**:

**Step 1: Write the test first** (TDD principle)

Create `test/test_episode_publisher_worker.rb`:

```ruby
require "minitest/autorun"
require "sidekiq/testing"
require_relative "../lib/workers/episode_publisher_worker"
require_relative "../lib/text_processor"
require_relative "../lib/tts"
require_relative "../lib/gcs_uploader"
require_relative "../lib/episode_manifest"
require_relative "../lib/podcast_publisher"

class TestEpisodePublisherWorker < Minitest::Test
  def setup
    Sidekiq::Testing.fake! # Don't actually process jobs in tests
  end

  def test_job_is_enqueued
    EpisodePublisherWorker.perform_async("title", "author", "description", "content")

    assert_equal 1, EpisodePublisherWorker.jobs.size
  end

  def test_job_parameters_are_stored
    EpisodePublisherWorker.perform_async(
      "My Title",
      "My Author",
      "My Description",
      "# Markdown content"
    )

    job = EpisodePublisherWorker.jobs.first
    assert_equal "My Title", job["args"][0]
    assert_equal "My Author", job["args"][1]
    assert_equal "My Description", job["args"][2]
    assert_equal "# Markdown content", job["args"][3]
  end
end
```

**Step 2: Run the test (it should fail)**

```bash
ruby test/test_episode_publisher_worker.rb
# Expected: LoadError - cannot load such file -- ../lib/workers/episode_publisher_worker
```

This is expected! We haven't created the worker yet. This is TDD: write the test, watch it fail, then implement.

**Step 3: Create the worker implementation**

Create directory and file:
```bash
mkdir -p lib/workers
```

Create `lib/workers/episode_publisher_worker.rb`:

```ruby
require "sidekiq"
require "time"
require "securerandom"
require_relative "../text_processor"
require_relative "../tts"
require_relative "../gcs_uploader"
require_relative "../episode_manifest"
require_relative "../podcast_publisher"

# Sidekiq worker that processes episode publishing asynchronously
# Accepts episode metadata and markdown content, generates TTS audio,
# uploads to GCS, and updates the podcast RSS feed
class EpisodePublisherWorker
  include Sidekiq::Worker

  # Sidekiq options
  sidekiq_options queue: :default, retry: 3, backtrace: true

  # Main job execution method
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def perform(title, author, description, markdown_content)
    logger.info "Starting episode publishing: #{title}"

    # Step 1: Generate filename from title
    filename = generate_filename(title)

    # Step 2: Save markdown to GCS (for record keeping)
    save_markdown_to_gcs(filename, title, author, description, markdown_content)

    # Step 3: Process markdown to plain text
    text = TextProcessor.convert_to_plain_text(markdown_content)
    logger.info "Processed markdown: #{text.length} characters"

    # Step 4: Generate TTS audio
    tts = TTS.new
    audio_content = tts.synthesize(text, voice: ENV.fetch("TTS_VOICE", "en-GB-Chirp3-HD-Enceladus"))
    logger.info "Generated audio: #{audio_content.bytesize} bytes"

    # Step 5: Save MP3 locally (temporary)
    mp3_path = save_mp3_locally(filename, audio_content)
    logger.info "Saved MP3 to: #{mp3_path}"

    # Step 6: Publish to podcast feed
    publish_episode(mp3_path, title, author, description)

    # Step 7: Cleanup local file
    File.delete(mp3_path) if File.exist?(mp3_path)

    logger.info "Episode published successfully: #{title}"
  rescue StandardError => e
    logger.error "Episode publishing failed: #{e.class} - #{e.message}"
    logger.error e.backtrace.join("\n")
    raise # Re-raise so Sidekiq can retry
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
    logger.info "Saved markdown to GCS: input/#{filename}.md"
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
end
```

**Step 4: Run tests**

```bash
ruby test/test_episode_publisher_worker.rb
# Should pass now
```

**Step 5: Run all tests to ensure nothing broke**

```bash
rake test
# All tests should pass
```

**Step 6: Check code style**

```bash
rake rubocop
# Fix any issues reported
```

**Testing Notes**:
- We test job enqueueing, not the full execution (that would require mocking many services)
- Integration testing will happen when we test the full API endpoint
- The worker uses existing tested components (TextProcessor, TTS, etc.)

**Commit**:
```bash
git add lib/workers/ test/test_episode_publisher_worker.rb
git commit -m "Add EpisodePublisherWorker for async episode processing"
```

---

### Phase 2: Sinatra API Application

#### Task 2.1: Add Sinatra Dependencies

**What**: Add Sinatra and related gems for building the web API.

**Files to modify**:
- `Gemfile`

**What to do**:

1. Add Sinatra gems to `Gemfile`:
   ```ruby
   # Add after sidekiq gems
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

#### Task 2.2: Create Sinatra API App (Test First)

**What**: Create the main Sinatra application with the `/publish` endpoint.

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
require "sidekiq/testing"
require_relative "../api"

class TestAPI < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    Sidekiq::Testing.fake!
    ENV["API_SECRET_TOKEN"] = "test-token-123"
  end

  def teardown
    Sidekiq::Worker.clear_all
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

    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
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
    post "/publish", valid_params, auth_header
    assert_equal 200, last_response.status
  end

  def test_valid_request_returns_success_json
    post "/publish", valid_params, auth_header

    body = JSON.parse(last_response.body)
    assert_equal "success", body["status"]
    assert_equal "Episode submitted for processing", body["message"]
  end

  def test_valid_request_enqueues_job
    post "/publish", valid_params, auth_header

    assert_equal 1, EpisodePublisherWorker.jobs.size

    job = EpisodePublisherWorker.jobs.first
    assert_equal "Test Title", job["args"][0]
    assert_equal "Test Author", job["args"][1]
    assert_equal "Test Description", job["args"][2]
    assert_includes job["args"][3], "# Test Content"
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
require "sidekiq"
require_relative "lib/workers/episode_publisher_worker"

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

  # Step 5: Enqueue background job
  EpisodePublisherWorker.perform_async(title, author, description, markdown_content)

  # Step 6: Return success
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
```

**Step 4: Run tests**

```bash
ruby test/test_api.rb
# Should pass
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

**Testing the API manually** (optional but recommended):

Start Redis:
```bash
redis-server
```

In another terminal, start Sidekiq:
```bash
bundle exec sidekiq -r ./lib/workers/episode_publisher_worker.rb
```

In another terminal, start the API:
```bash
API_SECRET_TOKEN=test123 ruby api.rb
```

In another terminal, test with curl:
```bash
# Create a test markdown file
echo "# Test Article" > /tmp/test.md

# Test the API
curl -X POST http://localhost:8080/publish \
  -H "Authorization: Bearer test123" \
  -F "title=Test Episode" \
  -F "author=Test Author" \
  -F "description=Test Description" \
  -F "content=@/tmp/test.md"

# Should return: {"status":"success","message":"Episode submitted for processing"}
```

**Commit**:
```bash
git add api.rb test/test_api.rb
git commit -m "Add Sinatra API with /publish endpoint"
```

---

#### Task 2.3: Update Environment Variables

**What**: Add new required environment variables for the API.

**Files to modify**:
- `.env.example`

**What to do**:

Add to `.env.example`:
```bash
# API Configuration
API_SECRET_TOKEN=your-secret-token-here

# Redis Configuration (for Sidekiq)
REDIS_URL=redis://localhost:6379/0

# TTS Voice (optional, defaults to en-GB-Chirp3-HD-Enceladus)
TTS_VOICE=en-GB-Chirp3-HD-Enceladus

# Port for local development (optional, defaults to 8080)
PORT=8080
```

Update your local `.env` file with actual values:
```bash
echo "API_SECRET_TOKEN=$(openssl rand -hex 32)" >> .env
echo "REDIS_URL=redis://localhost:6379/0" >> .env
```

**Testing**: No tests needed for env file examples.

**Commit**:
```bash
git add .env.example
git commit -m "Add API and Redis environment variables"
```

---

### Phase 3: Containerization & Deployment

#### Task 3.1: Create Dockerfile

**What**: Create a Dockerfile to containerize the application for Google Cloud Run.

**Files to create**:
- `Dockerfile`
- `.dockerignore`

**What to do**:

Create `Dockerfile`:
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
COPY . .

# Create output directory
RUN mkdir -p output

# Expose port
EXPOSE 8080

# Start application
# Cloud Run sets PORT environment variable
CMD ["bundle", "exec", "ruby", "api.rb"]
```

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

**Testing Dockerfile locally**:

1. Build the image:
   ```bash
   docker build -t podcast-api .
   ```

2. Run the container:
   ```bash
   docker run -p 8080:8080 \
     -e API_SECRET_TOKEN=test123 \
     -e GOOGLE_CLOUD_PROJECT=your-project \
     -e GOOGLE_CLOUD_BUCKET=your-bucket \
     -e GOOGLE_APPLICATION_CREDENTIALS=/app/credentials.json \
     -e REDIS_URL=redis://host.docker.internal:6379/0 \
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
git add Dockerfile .dockerignore
git commit -m "Add Dockerfile for Cloud Run deployment"
```

---

#### Task 3.2: Create Cloud Run Deployment Script

**What**: Create a script to simplify deployment to Google Cloud Run.

**Files to create**:
- `bin/deploy`

**What to do**:

Create `bin/deploy`:
```bash
#!/bin/bash
set -e

echo "================================"
echo "Deploying to Google Cloud Run"
echo "================================"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed"
    echo "Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check required environment variables
if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    echo "Error: GOOGLE_CLOUD_PROJECT not set"
    exit 1
fi

if [ -z "$GOOGLE_CLOUD_BUCKET" ]; then
    echo "Error: GOOGLE_CLOUD_BUCKET not set"
    exit 1
fi

if [ -z "$API_SECRET_TOKEN" ]; then
    echo "Error: API_SECRET_TOKEN not set"
    echo "Generate one with: openssl rand -hex 32"
    exit 1
fi

# Configuration
PROJECT_ID=$GOOGLE_CLOUD_PROJECT
SERVICE_NAME="podcast-api"
REGION="us-central1"
MEMORY="2Gi"
TIMEOUT="600s"
MAX_INSTANCES="1"
MIN_INSTANCES="0"

echo ""
echo "Configuration:"
echo "  Project: $PROJECT_ID"
echo "  Service: $SERVICE_NAME"
echo "  Region: $REGION"
echo "  Memory: $MEMORY"
echo "  Timeout: $TIMEOUT"
echo ""

# Deploy to Cloud Run
echo "Deploying..."
gcloud run deploy $SERVICE_NAME \
  --source . \
  --project $PROJECT_ID \
  --region $REGION \
  --platform managed \
  --allow-unauthenticated \
  --memory $MEMORY \
  --timeout $TIMEOUT \
  --max-instances $MAX_INSTANCES \
  --min-instances $MIN_INSTANCES \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
  --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET" \
  --set-env-vars "API_SECRET_TOKEN=$API_SECRET_TOKEN" \
  --set-env-vars "REDIS_URL=redis://REPLACE_WITH_REDIS_IP:6379/0"

echo ""
echo "================================"
echo "Deployment complete!"
echo "================================"
echo ""
echo "Get your service URL:"
echo "  gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'"
echo ""
echo "Test your API:"
echo "  curl -X POST https://YOUR_SERVICE_URL/publish \\"
echo "    -H \"Authorization: Bearer \$API_SECRET_TOKEN\" \\"
echo "    -F \"title=Test\" \\"
echo "    -F \"author=Test\" \\"
echo "    -F \"description=Test\" \\"
echo "    -F \"content=@article.md\""
```

Make it executable:
```bash
chmod +x bin/deploy
```

**Testing**: Can't fully test until we deploy, but verify the script runs:
```bash
bash -n bin/deploy  # Check syntax
```

**Important Note About Redis**:
Cloud Run is stateless, so we need a Redis instance for Sidekiq. Options:

1. **Redis Cloud** (recommended for production):
   - Sign up: https://redis.com/try-free/
   - Free tier: 30MB, good for small workloads
   - Get Redis URL and update REDIS_URL in deploy script

2. **Google Cloud Memorystore** (more expensive):
   - https://cloud.google.com/memorystore/docs/redis
   - Costs ~$50/month minimum

3. **In-memory (testing only)**:
   - Run without Redis for testing
   - Requires code changes (not recommended)

For now, we'll set up Redis Cloud in the next task.

**Commit**:
```bash
git add bin/deploy
git commit -m "Add Cloud Run deployment script"
```

---

#### Task 3.3: Set Up Redis Cloud for Production

**What**: Set up a managed Redis instance for Sidekiq in production.

**Why**: Cloud Run containers are stateless and ephemeral. We need a persistent Redis instance for the job queue.

**What to do**:

1. **Sign up for Redis Cloud**:
   - Go to: https://redis.com/try-free/
   - Create account (free tier available)
   - Create a new database

2. **Get connection details**:
   - Database endpoint (e.g., `redis-12345.c123.us-east-1-1.ec2.cloud.redislabs.com:12345`)
   - Password

3. **Format Redis URL**:
   ```
   redis://:YOUR_PASSWORD@redis-12345.c123.us-east-1-1.ec2.cloud.redislabs.com:12345/0
   ```

4. **Test connection locally**:
   ```bash
   # Add to your .env
   REDIS_URL=redis://:PASSWORD@your-redis-host:port/0

   # Test connection
   redis-cli -u $REDIS_URL ping
   # Should return: PONG
   ```

5. **Update deployment script**:
   Edit `bin/deploy` and replace the REDIS_URL line:
   ```bash
   --set-env-vars "REDIS_URL=$REDIS_URL"
   ```

6. **Add REDIS_URL to .env.example**:
   ```bash
   # Redis Configuration (for Sidekiq)
   # Local development: redis://localhost:6379/0
   # Production: redis://:PASSWORD@host:port/0 (from Redis Cloud)
   REDIS_URL=redis://localhost:6379/0
   ```

**Testing**: Test Redis connection:
```bash
bundle exec ruby -e "require 'redis'; redis = Redis.new(url: ENV['REDIS_URL']); puts redis.ping"
# Should output: PONG
```

**Commit**:
```bash
git add bin/deploy .env.example
git commit -m "Configure Redis Cloud for production Sidekiq"
```

---

#### Task 3.4: Deploy to Cloud Run

**What**: Deploy the application to Google Cloud Run.

**Prerequisites**:
- Completed all previous tasks
- Redis Cloud instance configured
- Google Cloud credentials set up

**What to do**:

1. **Verify .env has all required values**:
   ```bash
   cat .env | grep -E "(GOOGLE_CLOUD_PROJECT|GOOGLE_CLOUD_BUCKET|API_SECRET_TOKEN|REDIS_URL)"
   ```

2. **Source environment variables**:
   ```bash
   source .env
   ```

3. **Run deployment**:
   ```bash
   ./bin/deploy
   ```

4. **Get service URL**:
   ```bash
   gcloud run services describe podcast-api \
     --region us-central1 \
     --format 'value(status.url)'
   ```

   Save this URL! You'll use it for API calls.

5. **Test the deployed API**:

   Test health check:
   ```bash
   curl https://YOUR_SERVICE_URL.run.app/
   # Should return: {"status":"ok","message":"Podcast Publishing API"}
   ```

   Test authentication:
   ```bash
   curl -X POST https://YOUR_SERVICE_URL.run.app/publish
   # Should return 401 Unauthorized
   ```

   Test with valid request:
   ```bash
   # Create test file
   echo "# Test Article

   This is a test article." > /tmp/test-article.md

   # Submit episode
   curl -X POST https://YOUR_SERVICE_URL.run.app/publish \
     -H "Authorization: Bearer $API_SECRET_TOKEN" \
     -F "title=Test Episode $(date +%s)" \
     -F "author=API Tester" \
     -F "description=Testing the deployed API" \
     -F "content=@/tmp/test-article.md"

   # Should return: {"status":"success","message":"Episode submitted for processing"}
   ```

6. **Check logs for processing**:
   ```bash
   gcloud run logs read podcast-api --region us-central1 --limit 50
   ```

   Look for log entries showing:
   - "Starting episode publishing"
   - "Processed markdown"
   - "Generated audio"
   - "Episode published successfully"

7. **Verify episode in RSS feed**:
   ```bash
   # Get your GCS bucket's public URL
   echo "https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml"

   # Fetch and check feed
   curl https://storage.googleapis.com/$GOOGLE_CLOUD_BUCKET/feed.xml | grep "Test Episode"
   ```

**If deployment fails**:

- Check logs: `gcloud run logs read podcast-api --region us-central1 --limit 100`
- Verify environment variables are set
- Check Redis connection: Should see connection errors in logs if Redis is unreachable
- Verify Google Cloud credentials have correct permissions

**Commit** (if you made any changes):
```bash
git add .
git commit -m "Deploy podcast API to Cloud Run"
```

---

### Phase 4: Documentation & Finalization

#### Task 4.1: Create API Documentation

**What**: Document how to use the API for future reference.

**Files to create**:
- `docs/API.md`

**What to do**:

Create `docs/API.md`:
```markdown
# Podcast Publishing API Documentation

## Overview

HTTP API for publishing podcast episodes. Submit episode metadata and markdown content via POST request, and the system automatically generates audio, uploads to cloud storage, and updates the RSS feed.

## Base URL

Production: `https://YOUR_SERVICE_NAME.run.app`
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
curl -X POST https://YOUR_SERVICE_NAME.run.app/publish \
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

1. Episode is queued for background processing
2. System converts markdown to plain text
3. Text-to-speech audio is generated (30-60 seconds for typical articles)
4. Audio file is uploaded to Google Cloud Storage
5. RSS feed is updated with new episode
6. Original markdown is saved to GCS for records

Processing happens asynchronously. Check logs or RSS feed to verify completion.

## Monitoring

**View logs (Cloud Run):**
```bash
gcloud run logs read podcast-api --region us-central1 --limit 50
```

**Check RSS feed:**
```bash
curl https://storage.googleapis.com/YOUR_BUCKET/feed.xml
```

**Verify episode published:**
Look for your episode title in the RSS feed XML.

## Error Handling

Processing errors are logged but not returned to the client (since processing is asynchronous).

Common errors:
- **TTS rate limit exceeded**: Job will retry automatically (3 attempts)
- **Content filter triggered**: Check logs for details, may need to modify content
- **Upload failure**: Check GCS bucket permissions

## Local Development

1. Start Redis:
   ```bash
   redis-server
   ```

2. Start Sidekiq:
   ```bash
   bundle exec sidekiq -r ./lib/workers/episode_publisher_worker.rb
   ```

3. Start API:
   ```bash
   API_SECRET_TOKEN=test123 ruby api.rb
   ```

4. Test:
   ```bash
   curl -X POST http://localhost:8080/publish \
     -H "Authorization: Bearer test123" \
     -F "title=Test" \
     -F "author=Test" \
     -F "description=Test" \
     -F "content=@test.md"
   ```

## Cost Estimates

**Google Cloud Run:**
- Free tier: 2 million requests/month
- Expected cost: $0-5/month for personal use

**Redis Cloud:**
- Free tier: 30MB storage
- Expected cost: $0/month for personal use

**Google Cloud TTS:**
- $16 per 1 million characters (WaveNet voices)
- Example: 10,000-character article = ~$0.16

**Google Cloud Storage:**
- $0.02 per GB/month
- Example: 100 episodes at 5MB each = $0.01/month

**Total estimated cost:** $1-10/month depending on usage
```

**Commit**:
```bash
git add docs/API.md
git commit -m "Add API documentation"
```

---

#### Task 4.2: Update README

**What**: Update the main README to document the new API.

**Files to modify**:
- `README.md`

**What to do**:

Add a new section to `README.md` after the "Usage" section:

```markdown
## API Usage

You can also publish episodes via HTTP API:

```bash
curl -X POST https://your-service.run.app/publish \
  -H "Authorization: Bearer YOUR_SECRET_TOKEN" \
  -F "title=Episode Title" \
  -F "author=Author Name" \
  -F "description=Episode description" \
  -F "content=@path/to/article.md"
```

Returns immediately with `{"status":"success"}`. Processing happens in the background.

See [API Documentation](docs/API.md) for full details.

### Deployment

Deploy to Google Cloud Run:

```bash
./bin/deploy
```

See [API Documentation](docs/API.md) for setup instructions.
```

**Commit**:
```bash
git add README.md
git commit -m "Update README with API usage instructions"
```

---

#### Task 4.3: Final Testing Checklist

**What**: Perform end-to-end testing to verify everything works.

**Testing Checklist**:

- [ ] **Unit tests pass**: `rake test`
- [ ] **Code style passes**: `rake rubocop`
- [ ] **Docker builds**: `docker build -t podcast-api .`
- [ ] **Local API works**:
  - [ ] Start Redis: `redis-server`
  - [ ] Start Sidekiq: `bundle exec sidekiq -r ./lib/workers/episode_publisher_worker.rb`
  - [ ] Start API: `API_SECRET_TOKEN=test123 ruby api.rb`
  - [ ] Health check: `curl http://localhost:8080/`
  - [ ] Auth failure: `curl -X POST http://localhost:8080/publish` (expect 401)
  - [ ] Valid submission: Create test markdown file and submit
  - [ ] Check Sidekiq logs for processing
- [ ] **Deployed API works**:
  - [ ] Health check works
  - [ ] Auth required
  - [ ] Can submit episode
  - [ ] Episode appears in RSS feed (wait 2-3 minutes)
  - [ ] Audio file playable
  - [ ] Markdown saved to GCS
- [ ] **Documentation is complete**:
  - [ ] API.md has correct URLs
  - [ ] README has API section
  - [ ] .env.example has all variables

**Running all tests**:
```bash
rake test
rake rubocop
```

**Final deployment**:
```bash
./bin/deploy
```

---

## Troubleshooting Guide

### Common Issues

**Issue: "LoadError: cannot load such file -- sidekiq"**
- Solution: Run `bundle install`

**Issue: "Redis::CannotConnectError"**
- Solution: Start Redis locally (`redis-server`) or check REDIS_URL
- For Cloud Run: Verify Redis Cloud credentials

**Issue: "401 Unauthorized" when testing API**
- Solution: Check API_SECRET_TOKEN is set and matches in request

**Issue: "Episode not appearing in RSS feed"**
- Check Sidekiq logs for errors
- Verify GCS bucket permissions
- Check Cloud Run logs: `gcloud run logs read podcast-api --region us-central1`

**Issue: "TTS API quota exceeded"**
- Wait for quota reset (resets daily)
- Check quota: https://console.cloud.google.com/iam-admin/quotas
- Request increase if needed

**Issue: "Docker build fails"**
- Check Dockerfile syntax
- Ensure Gemfile.lock is committed
- Try: `docker system prune -a` and rebuild

**Issue: "Cloud Run deployment fails"**
- Check gcloud authentication: `gcloud auth list`
- Verify project: `gcloud config get-value project`
- Check billing is enabled
- Review error in deployment output

### Getting Help

**View Cloud Run logs:**
```bash
gcloud run logs read podcast-api --region us-central1 --limit 100
```

**View Sidekiq queue status:**
```bash
bundle exec ruby -e "require 'sidekiq/api'; puts Sidekiq::Queue.new.size"
```

**Test Redis connection:**
```bash
redis-cli -u $REDIS_URL ping
```

**Check GCS bucket access:**
```bash
gsutil ls gs://$GOOGLE_CLOUD_BUCKET/
```

---

## Summary

### What We Built

1. **Background Job System**: Sidekiq worker for async episode processing
2. **HTTP API**: Sinatra app with authentication and validation
3. **Containerization**: Docker setup for Cloud Run
4. **Deployment**: Scripts and configuration for Google Cloud Run
5. **Documentation**: Complete API docs and usage instructions

### Architecture

```
User → API (Cloud Run) → Sidekiq → Worker → [TTS, GCS, RSS] → Published Episode
         ↓
       Redis Cloud (Job Queue)
```

### Key Files Created

- `lib/workers/episode_publisher_worker.rb` - Background job processor
- `api.rb` - Sinatra web application
- `Dockerfile` - Container definition
- `bin/deploy` - Deployment script
- `config/sidekiq.yml` - Sidekiq configuration
- `docs/API.md` - API documentation
- Tests for all components

### Testing Strategy

- **Unit tests**: Test job enqueueing and API endpoints
- **Integration**: Manual testing of full flow
- **Mocking**: Mock external services in tests
- **TDD**: Write tests before implementation

### Deployment

Production URL: `https://podcast-api-[hash].run.app`

Usage:
```bash
curl -X POST https://your-url.run.app/publish \
  -H "Authorization: Bearer $API_SECRET_TOKEN" \
  -F "title=Title" \
  -F "author=Author" \
  -F "description=Description" \
  -F "content=@article.md"
```

### Costs

- **Cloud Run**: $0-5/month (free tier covers most personal use)
- **Redis Cloud**: $0/month (free tier)
- **GCS + TTS**: $1-5/month depending on usage

**Total: ~$5/month for moderate usage**

---

## Next Steps (Future Enhancements)

Not in scope for this plan, but potential improvements:

1. **Job status endpoint**: `GET /status/:job_id` to check processing status
2. **Webhook notifications**: Notify when processing completes/fails
3. **Episode management**: List, update, delete episodes
4. **Multiple voices**: Support different voices per episode
5. **Scheduled publishing**: Specify publish time in future
6. **Analytics**: Track episode downloads and plays
7. **Email publishing**: Send articles via email
8. **Web UI**: Simple form interface instead of cURL

---

## Principles Followed

- **DRY**: Reused existing components (TextProcessor, TTS, PodcastPublisher)
- **YAGNI**: Built only what's needed, no premature features
- **TDD**: Wrote tests before implementation
- **Frequent commits**: Each task = one commit
- **Separation of concerns**: API, worker, and publishing logic separate
- **12-factor app**: Config via environment, stateless processes
- **Fail fast**: Validation at API layer, detailed error logging

---

End of implementation plan.
