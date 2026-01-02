# frozen_string_literal: true

require "test_helper"

class PasteEpisodeFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(account_type: :unlimited)
    sign_in_as(@user)

    Mocktail.replace(ProcessesWithLlm)
    Mocktail.replace(SubmitEpisodeForProcessing)
  end

  test "full paste episode flow from form to completion" do
    text = "A" * 200

    # Submit the form
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      post episodes_url, params: { text: text }
    end

    assert_redirected_to episodes_path

    # Find the created episode
    episode = Episode.last
    assert_equal "paste", episode.source_type
    assert_equal "processing", episode.status
    assert_equal text, episode.source_text

    # Mock LLM response
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Generated Title",
      author: "Generated Author",
      description: "Generated description.",
      content: "Cleaned content."
    ))
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { true }

    # Process the job
    perform_enqueued_jobs

    # Verify final state
    episode.reload
    assert_equal "Generated Title", episode.title
    assert_equal "Generated Author", episode.author
    assert_equal "Generated description.", episode.description
  end

  teardown do
    Mocktail.reset
  end
end
