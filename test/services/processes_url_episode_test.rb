# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ProcessesUrlEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(account_type: :unlimited)
    @podcast = podcasts(:one)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Placeholder",
      author: "Placeholder",
      description: "Placeholder",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :pending
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
    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.failure("Could not fetch URL") }
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.failure("Could not fetch content from reader service") }

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Could not fetch URL", @episode.error_message
  end

  test "falls back to Jina when direct fetch fails" do
    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.failure("Could not fetch URL") }

    jina_markdown = "# Article Title\n\nFull article content fetched via Jina reader."
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.success(jina_markdown) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Article Title",
      author: "Author",
      description: "Description.",
      content: "Full article content."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "preparing", @episode.status, "Episode should succeed via Jina fallback; error: #{@episode.error_message}"
    verify { |_m| FetchesJinaContent.call(url: @episode.source_url) }
    verify { |m| ProcessesWithLlm.call(text: jina_markdown, episode: m.any) }
  end

  test "marks episode as failed when content too long for tier" do
    # Character limit applies to non-unlimited users; flip this user back
    # to free for this test so ValidatesCharacterLimit enforces the cap.
    @user.update!(account_type: :standard)
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
    assert_equal "preparing", @episode.status, "Episode should not have failed; error: #{@episode.error_message}"

    # Verify Jina was called as a fallback
    verify { |_m| FetchesJinaContent.call(url: @episode.source_url) }
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
    assert_equal "preparing", @episode.status, "Episode should not have failed; error: #{@episode.error_message}"

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
    verify { |_m| FetchesJinaContent.call(url: @episode.source_url) }

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

  test "uses known author mapping when HTML and extraction have no author" do
    html = "<article><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p></article>"

    @episode.update!(source_url: "https://www.seangoedecke.com/some-article")

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Some Article",
      author: "Unknown",
      description: "A blog post.",
      content: "Article content here."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Sean Goedecke", @episode.author,
      "Should use known author mapping when HTML extraction returns no author"
  end

  # === URL credit debit (deferred from controller) ===
  #
  # Controllers can't know the article length for URL submissions at
  # pre-check time. The actual debit lands here, once the fetched and
  # extracted text has been measured — so Premium + >20k URLs get
  # correctly charged 2 credits instead of silently 1.

  test "debits 1 credit when Standard voice and short article" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix") # Standard
    CreditBalance.for(credit_user).update!(balance: 3)
    episode = create_url_episode(credit_user)

    html = "<article><h1>Title</h1><p>#{"A" * 10_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { standard_llm_result }
    stub_gcs_and_tasks

    assert_difference -> { CreditTransaction.where(user: credit_user, transaction_type: "usage").count }, 1 do
      ProcessesUrlEpisode.call(episode: episode)
    end

    transaction = CreditTransaction.where(user: credit_user).order(:created_at).last
    assert_equal(-1, transaction.amount)
    assert_equal 2, credit_user.reload.credits_remaining

    episode.reload
    assert_not_equal "failed", episode.status
  end

  test "debits 2 credits when Premium voice and long article with sufficient balance" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium
    CreditBalance.for(credit_user).update!(balance: 2)
    episode = create_url_episode(credit_user)

    html = "<article><h1>Title</h1><p>#{"A" * 40_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { standard_llm_result }
    stub_gcs_and_tasks

    assert_difference -> { CreditTransaction.where(user: credit_user, transaction_type: "usage").count }, 1 do
      ProcessesUrlEpisode.call(episode: episode)
    end

    transaction = CreditTransaction.where(user: credit_user).order(:created_at).last
    assert_equal(-2, transaction.amount)
    assert_equal 0, credit_user.reload.credits_remaining

    episode.reload
    assert_not_equal "failed", episode.status
  end

  test "fails episode and skips TTS when Premium voice and long article with balance 1" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium
    CreditBalance.for(credit_user).update!(balance: 1)
    episode = create_url_episode(credit_user)

    html = "<article><h1>Title</h1><p>#{"A" * 40_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stub_gcs_and_tasks

    assert_no_difference -> { CreditTransaction.count } do
      ProcessesUrlEpisode.call(episode: episode)
    end

    episode.reload
    assert_equal "failed", episode.status
    assert_includes episode.error_message, "Insufficient credits"
    assert_equal 1, credit_user.reload.credits_remaining
    verify(times: 0) { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }
    verify(times: 0) { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }
  end

  test "fails episode and skips TTS when Standard voice and balance 0" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix") # Standard
    CreditBalance.for(credit_user).update!(balance: 0)
    episode = create_url_episode(credit_user)

    html = "<article><h1>Title</h1><p>#{"A" * 10_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stub_gcs_and_tasks

    assert_no_difference -> { CreditTransaction.count } do
      ProcessesUrlEpisode.call(episode: episode)
    end

    episode.reload
    assert_equal "failed", episode.status
    assert_includes episode.error_message, "Insufficient credits"
    verify(times: 0) { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }
    verify(times: 0) { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }
  end

  test "does not debit credits for complimentary user" do
    complimentary = users(:complimentary_user)
    complimentary.update!(voice_preference: "callum")
    episode = create_url_episode(complimentary)

    html = "<article><h1>Title</h1><p>#{"A" * 40_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { standard_llm_result }
    stub_gcs_and_tasks

    assert_no_difference -> { CreditTransaction.count } do
      ProcessesUrlEpisode.call(episode: episode)
    end

    episode.reload
    assert_not_equal "failed", episode.status
  end

  test "does not debit credits for unlimited user" do
    unlimited = users(:unlimited_user)
    unlimited.update!(voice_preference: "callum")
    episode = create_url_episode(unlimited)

    html = "<article><h1>Title</h1><p>#{"A" * 40_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { standard_llm_result }
    stub_gcs_and_tasks

    assert_no_difference -> { CreditTransaction.count } do
      ProcessesUrlEpisode.call(episode: episode)
    end

    episode.reload
    assert_not_equal "failed", episode.status
  end

  # === URL-path failure refund (agent-team-uoqd) ===
  #
  # If a URL episode fails AFTER deduct_credit has run (i.e. credits are
  # already gone), fail_episode must refund them via RefundsCreditDebit.
  # Before the fix, fail_episode only updated status → the credit stayed
  # debited and the user had to email support.

  test "refunds debited credit when URL episode fails after deduct_credit" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "felix") # Standard → 1 credit
    CreditBalance.for(credit_user).update!(balance: 3)
    episode = create_url_episode(credit_user)

    # Stub so deduct_credit succeeds (debits 1), then LLM fails → fail_episode fires.
    html = "<article><h1>Title</h1><p>#{"A" * 10_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with {
      Result.failure("LLM exploded")
    }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: episode)

    episode.reload
    assert_equal "failed", episode.status
    assert_equal 3, credit_user.reload.credits_remaining,
      "Credit should be refunded when URL episode fails after deduct_credit"
  end

  test "refunds 2 credits when premium URL episode fails after deduct_credit" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium
    CreditBalance.for(credit_user).update!(balance: 2)
    episode = create_url_episode(credit_user)

    # >20k chars + premium → 2-credit debit
    html = "<article><h1>Title</h1><p>#{"A" * 40_000}</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with {
      Result.failure("LLM exploded")
    }
    stub_gcs_and_tasks

    ProcessesUrlEpisode.call(episode: episode)

    episode.reload
    assert_equal "failed", episode.status
    assert_equal 2, credit_user.reload.credits_remaining,
      "Both debited credits should be refunded on URL-path failure"
  end

  teardown do
    Mocktail.reset
  end

  private

  def stub_gcs_and_tasks
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }
  end

  def create_url_episode(user)
    Episode.create!(
      podcast: user.podcasts.first || CreatesDefaultPodcast.call(user: user),
      user: user,
      title: "Placeholder",
      author: "Placeholder",
      description: "Placeholder",
      source_type: :url,
      source_url: "https://example.com/article",
      status: :pending
    )
  end

  def standard_llm_result
    Result.success(ProcessesWithLlm::LlmData.new(
      title: "Title",
      author: "Author",
      description: "Description.",
      content: "Article content."
    ))
  end
end
