# frozen_string_literal: true

require "test_helper"

class ProcessesFileEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @long_content = "# Test Header\n\n" + ("Some **bold** content here. " * 9) + "Some **bold** content here."
    @episode.update!(
      source_type: :file,
      source_text: @long_content,
      title: "Test Title",
      author: "Test Author"
    )

    Mocktail.replace(SubmitEpisodeForProcessing)
  end

  test "strips markdown and submits for processing" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { nil }

    ProcessesFileEpisode.call(episode: @episode)

    calls = Mocktail.calls(SubmitEpisodeForProcessing, :call)
    assert_equal 1, calls.size
    expected_plain = "Test Header\n\n" + ("Some bold content here. " * 9) + "Some bold content here."
    assert_equal expected_plain, calls.first.kwargs[:content]
  end

  test "marks episode as failed on error" do
    stubs { |m| SubmitEpisodeForProcessing.call(episode: m.any, content: m.any) }.with { raise StandardError, "Upload failed" }

    ProcessesFileEpisode.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Upload failed", @episode.error_message
  end
end
