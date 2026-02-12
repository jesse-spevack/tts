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
    assert_equal "A great article.\n\nOriginal URL: https://example.com/article", @episode.description
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
    assert_equal "LLM description.\n\nOriginal URL: https://example.com/article", @episode.description
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

  # -- Jina fallback tests --

  test "normal extraction does not trigger Jina fallback" do
    # HTML with enough extractable content (>= 500 chars) should NOT call Jina
    good_content = "A" * 600
    html = "<article><h1>Good Article</h1><p>#{good_content}</p></article>"

    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Good Article",
      author: "Author",
      description: "A good article.",
      content: "Processed content."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Good Article", @episode.title

    # FetchesJinaContent should never be called for high-quality extractions
    verify(times: 0) { |m| FetchesJinaContent.call(url: m.any) }
  end

  test "low-quality extraction triggers Jina fallback" do
    # Simulate JS-rendered page: large HTML (> 10KB) but little extractable text (< 500 chars)
    # The body has ~200 chars of real content (passes MIN_LENGTH=100 but below 500 threshold)
    # The bulk is in script tags which ExtractsArticle strips
    js_bulk = "var data = '#{" " * 12_000}';"
    small_content = "B" * 200
    html = <<~HTML
      <html>
        <head><title>JS App</title></head>
        <body>
          <script>#{js_bulk}</script>
          <article><p>#{small_content}</p></article>
        </body>
      </html>
    HTML

    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    jina_markdown = "# Minions\n\nStripe's one-shot end-to-end coding agents are transforming how we build software."
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.success(jina_markdown) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Minions",
      author: "Stripe Engineering",
      description: "About coding agents.",
      content: "Full article content from Jina."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "processing", @episode.status, "Episode should not have failed; error: #{@episode.error_message}"

    # Verify Jina was called as a fallback
    verify { |m| FetchesJinaContent.call(url: @episode.source_url) }
  end

  test "Jina fallback content is passed to LLM processing" do
    # Same low-quality setup: large HTML, little extractable text
    js_bulk = "var x = '#{" " * 12_000}';"
    small_content = "C" * 200
    html = <<~HTML
      <html>
        <head><title>SPA Page</title></head>
        <body>
          <script>#{js_bulk}</script>
          <article><p>#{small_content}</p></article>
        </body>
      </html>
    HTML

    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    jina_markdown = "# Real Article\n\nThis is the full rendered content from the Jina Reader API with all the details."
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.success(jina_markdown) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Real Article",
      author: "Author",
      description: "Description.",
      content: "Full content."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    # The Jina markdown — not the original poor extraction — should be passed to LLM
    verify { |m| ProcessesWithLlm.call(text: jina_markdown, episode: m.any) }
    assert_not_equal "failed", @episode.reload.status
  end

  test "Jina fallback preserves original HTML title and author" do
    # Low-quality extraction setup with HTML that has <title> and <meta author>
    js_bulk = "var y = '#{" " * 12_000}';"
    small_content = "D" * 200
    html = <<~HTML
      <html>
        <head>
          <title>JS Page Title</title>
          <meta name="author" content="HTML Author Name">
        </head>
        <body>
          <script>#{js_bulk}</script>
          <article><p>#{small_content}</p></article>
        </body>
      </html>
    HTML

    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    jina_markdown = "# Great Title\n\nBy Some Author\n\nDetailed article content from Jina that is comprehensive."
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.success(jina_markdown) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "LLM Title",
      author: "LLM Author",
      description: "A detailed article.",
      content: "Full article content."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload

    # After Jina fallback, the episode should complete successfully
    assert_equal "processing", @episode.status, "Episode should not have failed; error: #{@episode.error_message}"

    # The LLM should receive the Jina markdown as the text to process
    verify { |m| ProcessesWithLlm.call(text: jina_markdown, episode: m.any) }

    # The episode title/author should come from the original HTML extraction,
    # NOT from the LLM. The Jina fallback should preserve original metadata.
    assert_equal "JS Page Title", @episode.title,
      "Title should come from original HTML <title> tag, not LLM"
    assert_equal "HTML Author Name", @episode.author,
      "Author should come from original HTML <meta> tag, not LLM"
  end

  test "stripe.dev blog HTML triggers Jina fallback end-to-end" do
    # Uses the actual stripe.dev blog HTML (32,850 bytes) as a fixture.
    # ExtractsArticle yields only ~461 chars from this page (below the 500 threshold)
    # because the content is rendered via JS/React — proving the real-world need for Jina fallback.
    html = file_fixture("stripe_blog.html").read

    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    jina_markdown = <<~MARKDOWN
      # Minions: Stripe's one-shot, end-to-end coding agents

      By Alistair Gray

      At Stripe, we've developed a system of AI coding agents called Minions that can
      autonomously complete end-to-end engineering tasks. These agents handle everything
      from reading a task description to writing code, running tests, and submitting a
      pull request for review.

      ## How Minions work

      Each Minion receives a task and works independently to complete it. The system
      breaks down complex engineering problems into manageable steps, leveraging LLMs
      to understand codebases and generate appropriate solutions.
    MARKDOWN

    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.success(jina_markdown) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Minions: Stripe's one-shot, end-to-end coding agents",
      author: "Alistair Gray",
      description: "How Stripe built autonomous AI coding agents called Minions.",
      content: "Full processed article content about Stripe's Minions."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload

    # 1. Jina fallback was triggered (low-quality extraction detected)
    verify { |m| FetchesJinaContent.call(url: @episode.source_url) }

    # 2. Episode did not fail
    assert_not_equal "failed", @episode.status,
      "Episode should not have failed; error: #{@episode.error_message}"

    # 3. LLM received the Jina markdown, not the poor HTML extraction
    verify { |m| ProcessesWithLlm.call(text: jina_markdown, episode: m.any) }
  end

  test "continues with original extraction when Jina fallback fails" do
    # Simulate JS-rendered page: large HTML but little extractable text
    js_bulk = "var z = '#{" " * 12_000}';"
    small_content = "E" * 200
    html = <<~HTML
      <html>
        <head><title>JS App</title></head>
        <body>
          <script>#{js_bulk}</script>
          <article><p>#{small_content}</p></article>
        </body>
      </html>
    HTML

    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.failure("Jina request failed") }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "JS App",
      author: "Author",
      description: "Description.",
      content: "Some content."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload

    # Pipeline should continue with original extraction, not hard-fail
    assert_not_equal "failed", @episode.status,
      "Episode should NOT hard-fail when Jina fallback fails; error: #{@episode.error_message}"

    # LLM should receive the original (low-quality) extracted text, not Jina content
    verify { |m| ProcessesWithLlm.call(text: "E" * 200, episode: m.any) }
  end

  teardown do
    Mocktail.reset
  end

  private

  def stub_gcs_and_tasks
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }
  end
end
