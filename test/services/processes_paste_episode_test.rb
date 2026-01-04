# frozen_string_literal: true

require "test_helper"

class ProcessesPasteEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @text = "This is the pasted article content that will be processed by the LLM to extract metadata and clean up for TTS conversion."
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: @text,
      status: :processing
    )

    Mocktail.replace(ProcessesWithLlm)
    Mocktail.replace(SubmitEpisodeForProcessing)
  end

  test "processes text and updates episode metadata" do
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Extracted Title",
      author: "Extracted Author",
      description: "Extracted description.",
      content: "Cleaned content for TTS."
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    ProcessesPasteEpisode.call(episode: @episode)

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
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    ProcessesPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_not_nil @episode.content_preview
  end

  test "marks episode as failed when content too long for tier" do
    @episode.update!(source_text: "x" * 20_000)

    ProcessesPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_includes @episode.error_message, "exceeds your plan's"
  end

  test "marks episode as failed on LLM error" do
    mock_llm_result = Result.failure("LLM processing failed")

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }

    ProcessesPasteEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "LLM processing failed", @episode.error_message
  end

  test "calls SubmitEpisodeForProcessing with cleaned content" do
    cleaned_content = "Cleaned content for TTS."
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Title",
      author: "Author",
      description: "Description",
      content: cleaned_content
    ))

    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    ProcessesPasteEpisode.call(episode: @episode)

    verify { |m| SubmitEpisodeForProcessing.call(episode: @episode, content: cleaned_content) }
    assert true
  end

  teardown do
    Mocktail.reset
  end
end
