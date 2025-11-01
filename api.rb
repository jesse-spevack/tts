require "sinatra"
require "sinatra/json"
require "google/cloud/tasks/v2"
require_relative "lib/gcs_uploader"
require_relative "lib/episode_processor"

# Configure Sinatra
set :port, ENV.fetch("PORT", 8080)
set :bind, "0.0.0.0"
set :show_exceptions, false

# Disable Rack::Protection for API (no browser-based CSRF concerns)
disable :protection

# Health check endpoint with environment validation
get "/health" do
  required_vars = %w[
    GOOGLE_CLOUD_PROJECT
    GOOGLE_CLOUD_BUCKET
    API_SECRET_TOKEN
  ]

  missing_vars = required_vars.reject { |var| ENV.fetch(var, nil) }

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
  halt 401, json(status: "error", message: "Unauthorized") unless authenticated?

  # Step 2: Validate required fields
  errors = validate_params
  halt 400, json(status: "error", message: errors.join(", ")) if errors.any?

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

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil))
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
  halt 400, json(status: "error", message: validation_error) if validation_error

  # Step 3: Extract parameters
  title = payload["title"]
  author = payload["author"]
  description = payload["description"]
  staging_path = payload["staging_path"]

  logger.info "Processing: #{title}"
  logger.info "Downloading from: #{staging_path}"

  # Step 4: Download markdown from GCS
  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil))
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

  token = auth_header.split.last
  expected_token = ENV.fetch("API_SECRET_TOKEN", nil)

  return false unless expected_token

  token == expected_token
end

# Helper: Validate publish params
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
    if content_file.is_a?(Hash) && content_file[:tempfile]
      # Check if file is empty
      content = content_file[:tempfile].read
      content_file[:tempfile].rewind # Reset for later reading
      errors << "Content file is empty" if content.strip.empty?
    else
      errors << "Missing content"
    end
  end

  errors
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
# rubocop:disable Metrics/MethodLength
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
# rubocop:enable Metrics/MethodLength
