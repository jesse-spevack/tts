require "test_helper"
require "minitest/mock"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get index" do
    get episodes_url
    assert_response :success
  end

  test "should get new" do
    get new_episode_url
    assert_response :success
  end

  test "should create episode" do
    # Set required env vars
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    # Create a temporary markdown file for upload
    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content\n\nThis is test markdown."),
      "text/markdown",
      original_filename: "test.md"
    )

    # Track calls to mock objects
    uploader_called = false
    enqueuer_called = false
    enqueuer_args = nil

    # Mock GCS uploader
    mock_uploader = Object.new
    mock_uploader.define_singleton_method(:upload_staging_file) do |content:, filename:|
      uploader_called = true
      "podcasts/test/staging/#{filename}"
    end

    # Mock Cloud Tasks enqueuer
    mock_enqueuer = Object.new
    mock_enqueuer.define_singleton_method(:enqueue_episode_processing) do |episode_id:, podcast_id:, staging_path:, metadata:|
      enqueuer_called = true
      enqueuer_args = { episode_id: episode_id, podcast_id: podcast_id, staging_path: staging_path, metadata: metadata }
      nil
    end

    GcsUploader.stub :new, mock_uploader do
      CloudTasksEnqueuer.stub :new, mock_enqueuer do
        assert_difference("Episode.count") do
          post episodes_url, params: {
            episode: {
              title: "Test Episode",
              author: "Test Author",
              description: "Test Description",
              content: file
            }
          }
        end
      end
    end

    assert_redirected_to episodes_path
    assert uploader_called, "GcsUploader#upload_staging_file was not called"
    assert enqueuer_called, "CloudTasksEnqueuer#enqueue_episode_processing was not called"

    # Verify enqueuer arguments
    assert_kind_of Integer, enqueuer_args[:episode_id]
    assert_kind_of String, enqueuer_args[:podcast_id]
    assert_kind_of String, enqueuer_args[:staging_path]
    assert_equal "Test Episode", enqueuer_args[:metadata][:title]
    assert_equal "Test Author", enqueuer_args[:metadata][:author]
    assert_equal "Test Description", enqueuer_args[:metadata][:description]
  ensure
    ENV.delete("GOOGLE_CLOUD_BUCKET")
  end
end
