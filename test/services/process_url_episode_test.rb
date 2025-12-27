# frozen_string_literal: true

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

    Mocktail.replace(FetchesUrl)
    Mocktail.replace(ProcessesWithLlm)
    Mocktail.replace(SubmitEpisodeForProcessing)
  end

  test "processes URL and updates episode" do
    html = "<article><h1>Real Title</h1><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.success(html) }

    mock_llm_result = ProcessesWithLlm::Result.success(
      title: "Real Title",
      author: "John Doe",
      description: "A great article.",
      content: "Article content here."
    )

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Real Title", @episode.title
    assert_equal "John Doe", @episode.author
    assert_equal "A great article.", @episode.description
  end

  test "marks episode as failed on fetch error" do
    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.failure("Could not fetch URL") }

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not fetch URL", @episode.error_message
  end

  test "marks episode as failed when content too long for tier" do
    long_content = "x" * 20_000
    html = "<article><p>#{long_content}</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.success(html) }

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "too long"
  end

  test "marks episode as failed on extraction error" do
    html = "<html><body></body></html>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.success(html) }

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not extract article content", @episode.error_message
  end

  test "prefers HTML metadata over LLM results" do
    html = <<~HTML
      <html>
        <head>
          <title>HTML Title</title>
          <meta name="author" content="HTML Author">
        </head>
        <body>
          <article>
            <p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p>
          </article>
        </body>
      </html>
    HTML

    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.success(html) }

    mock_llm_result = ProcessesWithLlm::Result.success(
      title: "LLM Title",
      author: "LLM Author",
      description: "LLM description.",
      content: "Article content here."
    )

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "HTML Title", @episode.title
    assert_equal "HTML Author", @episode.author
    assert_equal "LLM description.", @episode.description
  end

  test "sets content_preview on episode from LLM content" do
    long_content = "B" * 100 + " middle " + "X" * 100
    # Use HTML with enough content to pass ArticleExtractor's minimum length
    html = "<article><h1>Title</h1><p>#{"x" * 200}</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { FetchesUrl::Result.success(html) }

    mock_llm_result = ProcessesWithLlm::Result.success(
      title: "Title",
      author: "Author",
      description: "Description",
      content: long_content
    )

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_not_nil @episode.content_preview, "content_preview should be set; episode status: #{@episode.status}, error: #{@episode.error_message}"
    assert @episode.content_preview.start_with?("B" * 57)
    assert @episode.content_preview.include?("... ")
    assert @episode.content_preview.end_with?("X" * 57)
  end

  test "normalizes substack URL before fetching" do
    @episode.update!(source_url: "https://open.substack.com/pub/testauthor/p/article?r=abc&utm_campaign=post")

    html = "<article><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed and analyzed by the system.</p></article>"

    # Expect the normalized URL to be used
    stubs { FetchesUrl.call(url: "https://testauthor.substack.com/p/article") }.with { FetchesUrl::Result.success(html) }

    mock_llm_result = ProcessesWithLlm::Result.success(
      title: "Title",
      author: "Author",
      description: "Description",
      content: "Content"
    )
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "processing", @episode.status
  end

  teardown do
    Mocktail.reset
  end

  private

  def stub_gcs_and_tasks
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }
  end
end
