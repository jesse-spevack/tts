# frozen_string_literal: true

require "test_helper"

class ProcessesEmailEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @text = "This is the email content that will be processed by the LLM to extract metadata and clean up for TTS conversion."
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing email content...",
      source_type: :email,
      source_text: @text,
      status: :processing
    )

    Mocktail.replace(ProcessesWithLlm)
    Mocktail.replace(SubmitsEpisodeForProcessing)
  end

  test "processes text and updates episode metadata" do
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Extracted Title",
      author: "Extracted Author",
      description: "Extracted description.",
      content: "Cleaned content for TTS."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    ProcessesEmailEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "Extracted Title", @episode.title
    assert_equal "Extracted Author", @episode.author
    assert_equal "Extracted description.", @episode.description
  end

  test "sets content_preview from LLM content" do
    long_content = "B" * 100 + " middle " + "X" * 100
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Title",
      author: "Author",
      description: "Description",
      content: long_content
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    ProcessesEmailEpisode.call(episode: @episode)

    @episode.reload
    assert_not_nil @episode.content_preview
  end

  test "marks episode as failed when content too long for tier" do
    @episode.update!(source_text: "x" * 20_000)

    ProcessesEmailEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "exceeds your plan's"
  end

  test "marks episode as failed on LLM error" do
    mock_llm_result = Result.failure("LLM processing failed")

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }

    ProcessesEmailEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "LLM processing failed", @episode.error_message
  end

  test "calls SubmitsEpisodeForProcessing with cleaned content" do
    cleaned_content = "Cleaned content for TTS."
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Title",
      author: "Author",
      description: "Description",
      content: cleaned_content
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| SubmitsEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    ProcessesEmailEpisode.call(episode: @episode)

    verify { |_m| SubmitsEpisodeForProcessing.call(episode: @episode, content: cleaned_content) }
    assert true
  end

  # === Credit refund on email-path failure (agent-team-uoqd round 2) ===
  #
  # Email episodes debit at CreatesEpisode#call. If the sync processor
  # fails, fail_episode must refund — same contract as paste/file/url.

  test "refunds debited credit when email episode fails on LLM error" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 3)

    episode = Episode.create!(
      podcast: podcasts(:one),
      user: credit_user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing email content...",
      source_type: :email,
      source_text: @text,
      status: :processing
    )

    DeductsCredit.call(user: credit_user, episode: episode, cost_in_credits: 1)
    assert_equal 2, credit_user.reload.credits_remaining

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { Result.failure("LLM exploded") }

    ProcessesEmailEpisode.call(episode: episode)

    episode.reload
    assert_equal "failed", episode.status
    assert_equal 3, credit_user.reload.credits_remaining,
      "Credit should be refunded when email episode fails after debit"
  end

  teardown do
    Mocktail.reset
  end
end
