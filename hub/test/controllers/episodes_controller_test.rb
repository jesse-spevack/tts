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

  test "passes nil max_characters to service for unlimited tier users" do
    sign_in_as users(:unlimited_user)

    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test content"),
      "text/markdown",
      original_filename: "test.md"
    )

    # Verify that the service is called with max_characters: nil for unlimited users
    mock_result = EpisodeSubmissionService::Result.success(episodes(:one))

    EpisodeSubmissionService.stub :call, ->(podcast:, user:, params:, uploaded_file:, max_characters:) {
      assert_nil max_characters, "Expected max_characters to be nil for unlimited tier users"
      mock_result
    } do
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

  test "allows free tier user to access new when under limit" do
    sign_in_as users(:free_user)

    get new_episode_url

    assert_response :success
  end

  test "redirects free tier user from new when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    get new_episode_url

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  test "allows free tier user to create when under limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content"),
      "text/markdown",
      original_filename: "test.md"
    )

    podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    podcast.users << free_user
    episode = podcast.episodes.create!(title: "Test", author: "A", description: "D", user: free_user)
    mock_result = EpisodeSubmissionService::Result.success(episode)

    EpisodeSubmissionService.stub :call, mock_result do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end

    assert_redirected_to episodes_path
  end

  test "redirects free tier user from create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content"),
      "text/markdown",
      original_filename: "test.md"
    )

    post episodes_url, params: {
      episode: { title: "Test", author: "A", description: "D", content: file }
    }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  test "records usage after successful submission for free tier user" do
    free_user = users(:free_user)
    sign_in_as free_user

    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content"),
      "text/markdown",
      original_filename: "test.md"
    )

    podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    podcast.users << free_user
    episode = podcast.episodes.create!(title: "Test", author: "A", description: "D", user: free_user)
    mock_result = EpisodeSubmissionService::Result.success(episode)

    assert_difference "EpisodeUsage.count", 1 do
      EpisodeSubmissionService.stub :call, mock_result do
        post episodes_url, params: {
          episode: { title: "Test", author: "A", description: "D", content: file }
        }
      end
    end

    usage = EpisodeUsage.current_for(free_user)
    assert_equal 1, usage.episode_count
  end

  test "does not record usage for non-free tier user" do
    sign_in_as users(:unlimited_user)

    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Test Content"),
      "text/markdown",
      original_filename: "test.md"
    )

    mock_episode = Episode.new(title: "Test", author: "A", description: "D")
    mock_episode.id = 999
    mock_result = EpisodeSubmissionService::Result.success(mock_episode)

    assert_no_difference "EpisodeUsage.count" do
      EpisodeSubmissionService.stub :call, mock_result do
        post episodes_url, params: {
          episode: { title: "Test", author: "A", description: "D", content: file }
        }
      end
    end
  end

  # URL-based episode creation tests

  test "create with url param creates URL episode and redirects" do
    assert_enqueued_with(job: ProcessUrlEpisodeJob) do
      post episodes_url, params: { url: "https://example.com/article" }
    end

    assert_redirected_to episodes_path
    follow_redirect!
    assert_match(/Processing/, response.body)
  end

  test "create with url param fails with invalid URL" do
    post episodes_url, params: { url: "not-a-url" }

    assert_response :unprocessable_entity
  end

  test "create with url param records episode usage for free tier" do
    free_user = users(:free_user)
    sign_in_as free_user

    assert_difference -> { EpisodeUsage.count }, 1 do
      post episodes_url, params: { url: "https://example.com/article" }
    end
  end

  test "redirects free tier user from URL create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    post episodes_url, params: { url: "https://example.com/article" }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  # Pagination tests

  test "index paginates episodes to 10 per page" do
    get episodes_url
    assert_response :success

    # Count episode cards rendered - should be 10 on first page
    # We have 13 episodes for podcast :one (one + 12 pagination fixtures)
    assert_select "[data-testid='episode-card']", count: 10
  end

  test "index shows second page when page param provided" do
    get episodes_url, params: { page: 2 }
    assert_response :success

    # Second page should have remaining 3 episodes
    assert_select "[data-testid='episode-card']", count: 3
  end

  test "index handles page beyond max by showing last page" do
    get episodes_url, params: { page: 999 }
    assert_response :success

    # Should not error, should show last page with remaining episodes
    assert_select "[data-testid='episode-card']"
  end

  test "index renders turbo frame for episodes list" do
    get episodes_url
    assert_response :success
    assert_select "turbo-frame#episodes_list"
  end

  test "index does not show pagination when 10 or fewer episodes" do
    # Delete pagination fixtures to have only 1 episode
    Episode.where(podcast: podcasts(:one)).where.not(id: episodes(:one).id).delete_all

    get episodes_url
    assert_response :success

    # Should not render pagination nav
    assert_select "nav.pagination", count: 0
  end
end
