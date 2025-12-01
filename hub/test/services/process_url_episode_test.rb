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

    Mocktail.replace(UrlFetcher)
    Mocktail.replace(LlmProcessor)
    Mocktail.replace(UploadAndEnqueueEpisode)
  end

  test "processes URL and updates episode" do
    html = "<article><h1>Real Title</h1><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p></article>"

    stubs { |m| UrlFetcher.call(url: m.any) }.with { UrlFetcher::Result.success(html) }

    mock_llm_result = LlmProcessor::Result.success(
      title: "Real Title",
      author: "John Doe",
      description: "A great article.",
      content: "Article content here."
    )

    stubs { |m| LlmProcessor.call(text: m.any, episode: m.any, user: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Real Title", @episode.title
    assert_equal "John Doe", @episode.author
    assert_equal "A great article.", @episode.description
  end

  test "marks episode as failed on fetch error" do
    stubs { |m| UrlFetcher.call(url: m.any) }.with { UrlFetcher::Result.failure("Could not fetch URL") }

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not fetch URL", @episode.error_message
  end

  test "marks episode as failed when content too long for tier" do
    long_content = "x" * 20_000
    html = "<article><p>#{long_content}</p></article>"

    stubs { |m| UrlFetcher.call(url: m.any) }.with { UrlFetcher::Result.success(html) }

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "too long"
  end

  test "marks episode as failed on extraction error" do
    html = "<html><body></body></html>"

    stubs { |m| UrlFetcher.call(url: m.any) }.with { UrlFetcher::Result.success(html) }

    ProcessUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not extract article content", @episode.error_message
  end

  teardown do
    Mocktail.reset
  end

  private

  def stub_gcs_and_tasks
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { true }
  end
end
