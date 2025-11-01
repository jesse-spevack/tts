require "minitest/autorun"
require "rack/test"
require "json"

# Set to test environment to disable Sinatra 4.x host authorization
ENV["RACK_ENV"] = "test"

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

  def test_health_check_returns_ok
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

  def test_missing_auth_header_returns_unauthorized
    post "/publish"
    assert_equal 401, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal "error", body["status"]
    assert_includes body["message"], "Unauthorized"
  end

  def test_invalid_auth_token_returns_unauthorized
    post "/publish", {}, { "HTTP_AUTHORIZATION" => "Bearer wrong-token" }
    assert_equal 401, last_response.status
  end

  def test_valid_auth_with_missing_data_returns_bad_request_not_unauthorized
    post "/publish", {}, auth_header
    assert_equal 400, last_response.status # Not 401
  end

  # Validation Tests

  def test_missing_title_returns_bad_request
    params = valid_params.except(:title)
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "title"
  end

  def test_missing_author_returns_bad_request
    params = valid_params.except(:author)
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "author"
  end

  def test_missing_description_returns_bad_request
    params = valid_params.except(:description)
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "description"
  end

  def test_missing_content_returns_bad_request
    params = valid_params.except(:content)
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "content"
  end

  def test_empty_content_returns_bad_request
    params = valid_params.merge(content: empty_file)
    post "/publish", params, auth_header

    assert_equal 400, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body["message"], "empty"
  end

  # Process Endpoint Tests

  def test_process_requires_json_payload
    post "/process", "not json", { "CONTENT_TYPE" => "application/json" }
    assert_equal 400, last_response.status
  end

  def test_process_validates_required_fields
    payload = {
      title: "Test",
      author: "Test Author",
      description: "Test description"
    }.to_json
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
