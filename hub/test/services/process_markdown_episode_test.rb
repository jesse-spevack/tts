# frozen_string_literal: true

require "test_helper"

class ProcessMarkdownEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(
      source_type: :file,
      source_text: "# Test Header\n\nSome **bold** content.",
      title: "Test Title",
      author: "Test Author"
    )

    Mocktail.replace(SubmitEpisodeForProcessing)
  end

  test "strips markdown and submits for processing" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { nil }

    ProcessMarkdownEpisode.call(episode: @episode)

    verify { |m| SubmitEpisodeForProcessing.call(episode: @episode, content: "Test Header\n\nSome bold content.") }
  end

  test "marks episode as failed on error" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { raise StandardError, "Upload failed" }

    ProcessMarkdownEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Upload failed", @episode.error_message
  end
end
