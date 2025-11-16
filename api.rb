require "sinatra"
require "sinatra/json"
require "net/http"
require "uri"
require_relative "lib/gcs_uploader"
require_relative "lib/episode_processor"
require_relative "lib/publish_params_validator"
require_relative "lib/cloud_tasks_enqueuer"
require_relative "lib/filename_generator"
require_relative "lib/hub_callback_client"

# Configure Sinatra
set :port, ENV.fetch("PORT", 8080)
set :bind, "0.0.0.0"
set :show_exceptions, false

# Configure Rack::Protection for API
# Disable JSON CSRF and Host Authorization for server-to-server API
# - json_csrf: Not needed for Bearer token authenticated APIs
# - host_authorization: Not needed with token auth, would block external requests
# Keep other protections enabled (XSS, frame options, path traversal, etc.)
set :protection, except: %i[json_csrf host_authorization]

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
  errors = PublishParamsValidator.new(params).validate
  halt 400, json(status: "error", message: errors.join(", ")) if errors.any?

  # Step 3: Handle episode submission
  handle_episode_submission(params)

  json status: "success", message: "Episode submitted for processing"
rescue StandardError => e
  logger.error "Error: #{e.class} - #{e.message}"
  logger.error e.backtrace.join("\n")
  halt 500, json(status: "error", message: "Internal server error")
end

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

# Helper: Check authentication
def authenticated?
  auth_header = request.env["HTTP_AUTHORIZATION"]
  return false unless auth_header

  token = auth_header.split.last
  expected_token = ENV.fetch("API_SECRET_TOKEN", nil)

  return false unless expected_token

  token == expected_token
end

# Helper: Handle episode submission
def handle_episode_submission(params)
  podcast_id = params[:podcast_id]
  title = params[:title]
  markdown_content = params[:content][:tempfile].read

  # Upload to staging
  staging_path = upload_to_staging(podcast_id: podcast_id, title: title, markdown_content: markdown_content)

  # Enqueue task
  enqueue_processing_task(params: params, staging_path: staging_path)
end

# Helper: Upload markdown content to GCS staging
def upload_to_staging(podcast_id:, title:, markdown_content:)
  filename = FilenameGenerator.generate(title)
  staging_path = "staging/#{filename}.md"

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
  gcs.upload_content(content: markdown_content, remote_path: staging_path)

  logger.info "event=file_uploaded podcast_id=#{podcast_id} title=\"#{title}\" staging_path=#{staging_path}"
  staging_path
end

# Helper: Enqueue episode processing task
def enqueue_processing_task(params:, staging_path:)
  task_payload = params.slice(:podcast_id, :title, :author, :description).merge(staging_path: staging_path)
  task_name = CloudTasksEnqueuer.new.enqueue_episode_processing(task_payload)
  logger.info "event=task_enqueued podcast_id=#{params[:podcast_id]} title=\"#{params[:title]}\" task_name=#{task_name}"
  logger.info "event=episode_submitted podcast_id=#{params[:podcast_id]} title=\"#{params[:title]}\""
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
  episode_id = payload["episode_id"] # Optional: Hub's episode ID for callback

  logger.info "event=processing_started podcast_id=#{podcast_id} title=\"#{title}\""

  # Download markdown from GCS
  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
  markdown_content = gcs.download_file(remote_path: staging_path)
  logger.info "event=file_downloaded podcast_id=#{podcast_id} size_bytes=#{markdown_content.bytesize}"

  # Process episode
  processor = EpisodeProcessor.new(ENV.fetch("GOOGLE_CLOUD_BUCKET"), podcast_id)
  episode_data = processor.process(title: title, author: author, description: description, markdown_content: markdown_content)
  logger.info "event=episode_processed podcast_id=#{podcast_id}"

  # Cleanup staging file
  gcs.delete_file(remote_path: staging_path)
  logger.info "event=staging_cleaned podcast_id=#{podcast_id} staging_path=#{staging_path}"

  # Notify Hub of completion (if episode_id provided)
  notify_hub_complete(episode_id: episode_id, episode_data: episode_data) if episode_id

  logger.info "event=processing_completed podcast_id=#{podcast_id}"
rescue StandardError => e
  # Notify Hub of failure (if episode_id provided)
  notify_hub_failed(episode_id: episode_id, error_message: e.message) if episode_id
  raise
end

# Helper: Notify Hub that episode processing completed
def notify_hub_complete(episode_id:, episode_data:)
  hub_url = ENV.fetch("HUB_CALLBACK_URL", nil)
  callback_secret = ENV.fetch("HUB_CALLBACK_SECRET", nil)

  return unless hub_url && callback_secret

  client = HubCallbackClient.new(hub_url: hub_url, callback_secret: callback_secret)
  response = client.notify_complete(episode_id: episode_id, episode_data: episode_data)
  logger.info "event=hub_callback_complete episode_id=#{episode_id} status=#{response.code}"
rescue StandardError => e
  logger.error "event=hub_callback_failed episode_id=#{episode_id} error=#{e.message}"
end

# Helper: Notify Hub that episode processing failed
def notify_hub_failed(episode_id:, error_message:)
  hub_url = ENV.fetch("HUB_CALLBACK_URL", nil)
  callback_secret = ENV.fetch("HUB_CALLBACK_SECRET", nil)

  return unless hub_url && callback_secret

  client = HubCallbackClient.new(hub_url: hub_url, callback_secret: callback_secret)
  response = client.notify_failed(episode_id: episode_id, error_message: error_message)
  logger.info "event=hub_failure_notified episode_id=#{episode_id} status=#{response.code}"
rescue StandardError => e
  logger.error "event=hub_callback_error episode_id=#{episode_id} error=#{e.message}"
end
