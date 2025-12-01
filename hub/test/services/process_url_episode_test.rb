require "test_helper"
require "ostruct"

class ProcessUrlEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Placeholder",
      author: "Placeholder",
      description: "Placeholder",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :processing
    )
  end

  test "processes URL and updates episode" do
    html = "<article><h1>Real Title</h1><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p></article>"

    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: html)

    mock_llm_result = LlmProcessor::Result.success(
      title: "Real Title",
      author: "John Doe",
      description: "A great article.",
      content: "Article content here."
    )

    mock_gcs = MockGcsUploader.new
    mock_tasks = MockCloudTasksEnqueuer.new
    mock_llm = MockLlmProcessor.new(mock_llm_result)

    ProcessUrlEpisode.call(
      episode: @episode,
      gcs_uploader: mock_gcs,
      tasks_enqueuer: mock_tasks,
      llm_processor: mock_llm
    )

    @episode.reload
    assert_equal "Real Title", @episode.title
    assert_equal "John Doe", @episode.author
    assert_equal "A great article.", @episode.description
  end

  test "marks episode as failed on fetch error" do
    stub_request(:get, "https://example.com/article")
      .to_return(status: 404)

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not fetch URL", @episode.error_message
  end

  test "marks episode as failed when content too long for tier" do
    long_content = "x" * 20_000
    html = "<article><p>#{long_content}</p></article>"

    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: html)

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "too long"
  end

  test "marks episode as failed on extraction error" do
    html = "<html><body></body></html>"

    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: html)

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not extract article content", @episode.error_message
  end

  class MockGcsUploader
    def upload_staging_file(content:, filename:)
      "staging/#{filename}"
    end
  end

  class MockCloudTasksEnqueuer
    def enqueue_episode_processing(**args)
      "task-123"
    end
  end

  class MockLlmProcessor
    def initialize(result)
      @result = result
    end

    def call(**args)
      @result
    end
  end
end
