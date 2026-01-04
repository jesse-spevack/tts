# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ProcessesUrlEpisodeTest < ActiveSupport::TestCase
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
    Mocktail.replace(SubmitsEpisodeForProcessing)
  end

  test "processes URL and updates episode" do
    html = "<article><h1>Real Title</h1><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Real Title",
      author: "John Doe",
      description: "A great article.",
      content: "Article content here."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Real Title", @episode.title
    assert_equal "John Doe", @episode.author
    assert_equal "A great article.", @episode.description
  end

  test "marks episode as failed on fetch error" do
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.failure("Could not fetch URL") }

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not fetch URL", @episode.error_message
  end

  test "marks episode as failed when content too long for tier" do
    long_content = "x" * 20_000
    html = "<article><p>#{long_content}</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "exceeds your plan's"
  end

  test "marks episode as failed on extraction error" do
    html = "<html><body></body></html>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    ProcessesUrlEpisode.call(episode: @episode)

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

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "LLM Title",
      author: "LLM Author",
      description: "LLM description.",
      content: "Article content here."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "HTML Title", @episode.title
    assert_equal "HTML Author", @episode.author
    assert_equal "LLM description.", @episode.description
  end

  test "sets content_preview on episode from LLM content" do
    long_content = "B" * 100 + " middle " + "X" * 100
    # Use HTML with enough content to pass ExtractsArticle's minimum length
    html = "<article><h1>Title</h1><p>#{"x" * 200}</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Title",
      author: "Author",
      description: "Description",
      content: long_content
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_not_nil @episode.content_preview, "content_preview should be set; episode status: #{@episode.status}, error: #{@episode.error_message}"
    assert @episode.content_preview.start_with?("B" * 57)
    assert @episode.content_preview.include?("... ")
    assert @episode.content_preview.end_with?("X" * 57)
  end

  teardown do
    Mocktail.reset
  end

  private

  def stub_gcs_and_tasks
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }
  end
end
