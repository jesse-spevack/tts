require "test_helper"
require "minitest/mock"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(tier: :unlimited)
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
    # Create a temporary markdown file for upload
    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content\n\nThis is test markdown."),
      "text/markdown",
      original_filename: "test.md"
    )

    # Mock the service to return success
    mock_episode = Episode.new(title: "Test Episode", author: "Test Author", description: "Test Description")
    mock_episode.id = 999
    mock_result = EpisodeSubmissionService::Result.success(mock_episode)

    EpisodeSubmissionService.stub :call, mock_result do
      post episodes_url, params: {
        episode: {
          title: "Test Episode",
          author: "Test Author",
          description: "Test Description",
          content: file
        }
      }
    end

    assert_redirected_to episodes_path
  end

  test "should render new on validation failure" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content"),
      "text/markdown",
      original_filename: "test.md"
    )

    # Mock the service to return failure
    mock_episode = Episode.new
    mock_episode.errors.add(:title, "can't be blank")
    mock_result = EpisodeSubmissionService::Result.failure(mock_episode)

    EpisodeSubmissionService.stub :call, mock_result do
      post episodes_url, params: {
        episode: {
          title: "",
          author: "",
          description: "",
          content: file
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should show error when no file uploaded" do
    # Mock the service to return failure with file error
    mock_episode = Episode.new(
      title: "Test Episode",
      author: "Test Author",
      description: "Test Description",
      status: "failed",
      error_message: "No file uploaded"
    )
    mock_result = EpisodeSubmissionService::Result.failure(mock_episode)

    EpisodeSubmissionService.stub :call, mock_result do
      post episodes_url, params: {
        episode: {
          title: "Test Episode",
          author: "Test Author",
          description: "Test Description",
          content: nil
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "No file uploaded"
  end
end
