require "test_helper"
require "minitest/mock"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(account_type: :unlimited)
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
    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
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
      StringIO.new(""),
      "text/markdown",
      original_filename: "test.md"
    )

    post episodes_url, params: {
      episode: {
        title: "Test",
        author: "Author",
        description: "Desc",
        content: file
      }
    }

    assert_response :unprocessable_entity
  end

  test "should show error when no file uploaded" do
    post episodes_url, params: {
      episode: {
        title: "Test Episode",
        author: "Test Author",
        description: "Test Description",
        content: nil
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Content cannot be empty"
  end

  test "unlimited tier users can create episodes" do
    sign_in_as users(:unlimited_user)

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
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

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
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

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
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

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_difference "EpisodeUsage.count", 1 do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end

    usage = EpisodeUsage.current_for(free_user)
    assert_equal 1, usage.episode_count
  end

  test "does not record usage for non-free tier user" do
    sign_in_as users(:unlimited_user)

    long_content = "# Test Content\n\n" + ("This is test markdown content. " * 10)
    file = Rack::Test::UploadedFile.new(
      StringIO.new(long_content),
      "text/markdown",
      original_filename: "test.md"
    )

    assert_no_difference "EpisodeUsage.count" do
      post episodes_url, params: {
        episode: { title: "Test", author: "A", description: "D", content: file }
      }
    end
  end

  # URL-based episode creation tests

  test "create with url param creates URL episode and redirects" do
    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
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

  # Paste text episode creation tests

  test "create with text param creates paste episode and redirects" do
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      post episodes_url, params: { text: "A" * 150 }
    end

    assert_redirected_to episodes_path
    follow_redirect!
    assert_match(/Processing/, response.body)
  end

  test "create with text param fails with empty text" do
    post episodes_url, params: { text: "" }

    assert_response :unprocessable_entity
  end

  test "create with text param fails with text under 100 characters" do
    post episodes_url, params: { text: "A" * 99 }

    assert_response :unprocessable_entity
  end

  test "create with text param records episode usage for free tier" do
    free_user = users(:free_user)
    sign_in_as free_user

    assert_difference -> { EpisodeUsage.count }, 1 do
      post episodes_url, params: { text: "A" * 150 }
    end
  end

  test "redirects free tier user from text create when at monthly limit" do
    free_user = users(:free_user)
    sign_in_as free_user

    EpisodeUsage.create!(
      user: free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    post episodes_url, params: { text: "A" * 150 }

    assert_redirected_to episodes_path
    assert_includes flash[:alert], "You've used your 2 free episodes this month"
  end

  # Pagination tests

  test "index paginates episodes to 10 per page" do
    get episodes_url
    assert_response :success

    # Count episode cards rendered - should be 10 on first page
    # We have 14 episodes for podcast :one (one + 12 pagination fixtures + failed_with_error)
    assert_select "[data-testid='episode-card']", count: 10
  end

  test "index shows second page when page param provided" do
    get episodes_url, params: { page: 2 }
    assert_response :success

    # Second page should have remaining 4 episodes
    assert_select "[data-testid='episode-card']", count: 4
  end

  test "index handles page beyond max by showing empty page" do
    get episodes_url, params: { page: 999 }
    assert_response :success

    # Pagy 43 returns empty page for out-of-range requests (no error, no episodes)
    assert_select "[data-testid='episode-card']", count: 0
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

  # Failed episode error message tests

  test "index displays error message for failed episodes" do
    # Use the failed_with_error fixture
    get episodes_url
    assert_response :success
    assert_includes response.body, "This content is too long for your account tier"
  end

  test "index does not display error styling for completed episodes" do
    # Delete the failed episode so we only have completed ones
    Episode.where(status: :failed).delete_all

    get episodes_url
    assert_response :success

    # Should not contain the error message paragraph with red styling
    assert_no_match(/text-\[var\(--color-red\)\].*mt-1/, response.body)
  end

  # Public episode show tests

  test "show renders episode page for complete episode without authentication" do
    sign_out
    episode = episodes(:two) # status: complete
    get episode_url(episode.prefix_id)
    assert_response :success
  end

  test "show returns 404 for non-complete episode" do
    sign_out
    episode = episodes(:one) # status: pending
    get episode_url(episode.prefix_id)
    assert_response :not_found
  end

  test "show returns 404 for non-existent episode" do
    sign_out
    get episode_url("ep_nonexistent")
    assert_response :not_found
  end

  test "show displays episode title" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "h1", text: episode.title
  end

  test "show displays audio player for complete episode" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "audio[controls]"
  end

  test "show works for authenticated users too" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_response :success
  end

  test "show displays download button" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "a[href=?]", episode_path(episode.prefix_id, format: :mp3), text: /Download MP3/
  end

  test "show displays copy link button" do
    episode = episodes(:two)
    get episode_url(episode.prefix_id)
    assert_select "button[data-controller='clipboard']"
  end

  test "show with mp3 format redirects to signed GCS URL" do
    episode = episodes(:two)

    # Stub the download_url method on the specific episode instance
    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"
    episode.define_singleton_method(:download_url) { signed_url }

    Episode.stub(:find_by_prefix_id!, episode) do
      get episode_url(episode.prefix_id, format: :mp3)
    end

    assert_redirected_to signed_url
  end

  test "show with mp3 format returns 404 for incomplete episode" do
    episode = episodes(:one)  # pending episode

    get episode_url(episode.prefix_id, format: :mp3)

    assert_response :not_found
  end

  test "show with mp3 format works without authentication" do
    sign_out
    episode = episodes(:two)

    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"
    episode.define_singleton_method(:download_url) { signed_url }

    Episode.stub(:find_by_prefix_id!, episode) do
      get episode_url(episode.prefix_id, format: :mp3)
    end

    assert_redirected_to signed_url
  end

  # Delete episode tests

  test "destroy soft-deletes the episode" do
    Mocktail.replace(CloudStorage)
    Mocktail.replace(GeneratesRssFeed)

    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GeneratesRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    episode = episodes(:one)

    perform_enqueued_jobs do
      delete episode_url(episode)
    end

    assert_not_nil Episode.unscoped.find(episode.id).deleted_at
  end

  test "destroy enqueues DeleteEpisodeJob with episode" do
    episode = episodes(:one)
    episode.update!(gcs_episode_id: "20251222-test")

    assert_enqueued_with(job: DeleteEpisodeJob) do
      delete episode_url(episode)
    end
  end

  test "destroy redirects to episodes index" do
    episode = episodes(:one)

    delete episode_url(episode)

    assert_redirected_to episodes_path
  end

  test "deleted episodes do not appear in index" do
    episode = episodes(:one)
    episode.soft_delete!

    get episodes_url

    assert_response :success
    assert_no_match episode.title, response.body
  end
end
