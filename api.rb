require "sinatra"
require "sinatra/json"
require_relative "lib/gcs_uploader"
require_relative "lib/episode_processor"
require_relative "lib/publish_params_validator"
require_relative "lib/cloud_tasks_enqueuer"
require_relative "lib/filename_generator"

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

  # Step 3: Extract parameters
  title = params[:title]
  author = params[:author]
  description = params[:description]
  content_file = params[:content]

  # Step 4: Read file content
  markdown_content = content_file[:tempfile].read

  # Step 5: Generate filename and upload to GCS staging
  filename = FilenameGenerator.generate(title)
  staging_path = "staging/#{filename}.md"

  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil))
  gcs.upload_content(content: markdown_content, remote_path: staging_path)

  logger.info "event=file_uploaded title=\"#{title}\" staging_path=#{staging_path}"

  # Step 6: Enqueue processing task
  task_name = CloudTasksEnqueuer.new.enqueue_episode_processing(title, author, description, staging_path)
  logger.info "event=task_enqueued title=\"#{title}\" task_name=#{task_name}"

  # Step 7: Return success immediately
  logger.info "event=episode_submitted title=\"#{title}\" staging_path=#{staging_path}"
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

# Helper: Validate task payload
def validate_task_payload(payload)
  return "Missing title" unless payload["title"]
  return "Missing author" unless payload["author"]
  return "Missing description" unless payload["description"]
  return "Missing staging_path" unless payload["staging_path"]

  nil # No errors
end

# Helper: Process episode from Cloud Task payload
def process_episode_task(payload)
  title = payload["title"]
  author = payload["author"]
  description = payload["description"]
  staging_path = payload["staging_path"]

  logger.info "event=processing_started title=\"#{title}\" staging_path=#{staging_path}"

  # Download markdown from GCS
  gcs = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil))
  markdown_content = gcs.download_file(remote_path: staging_path)
  logger.info "event=file_downloaded title=\"#{title}\" size_bytes=#{markdown_content.bytesize}"

  # Process episode
  processor = EpisodeProcessor.new
  processor.process(title, author, description, markdown_content)
  logger.info "event=episode_processed title=\"#{title}\""

  # Cleanup staging file
  gcs.delete_file(remote_path: staging_path)
  logger.info "event=staging_cleaned title=\"#{title}\" staging_path=#{staging_path}"

  logger.info "event=processing_completed title=\"#{title}\""
end
