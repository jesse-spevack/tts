# frozen_string_literal: true

require "test_helper"

class ProcessFileEpisodeTest < ActiveSupport::TestCase
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

    ProcessFileEpisode.call(episode: @episode)

    calls = Mocktail.calls(SubmitEpisodeForProcessing, :call)
    assert_equal 1, calls.size
    assert_equal "Test Header\n\nSome bold content.", calls.first.kwargs[:content]
  end

  test "marks episode as failed on error" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { raise StandardError, "Upload failed" }

    ProcessFileEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Upload failed", @episode.error_message
  end
end
