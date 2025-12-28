# frozen_string_literal: true

require "test_helper"

class ProcessFileEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:one)
    @long_content = "# Test markdown\n\n" + ("Content here for testing. " * 10)
    @episode.update!(source_type: :file, source_text: @long_content)
    Mocktail.replace(ProcessFileEpisode)
  end

  test "calls ProcessFileEpisode with episode" do
    stubs { |m| ProcessFileEpisode.call(episode: m.any) }.with { nil }

    ProcessFileEpisodeJob.perform_now(@episode.id)

    assert_equal 1, Mocktail.calls(ProcessFileEpisode, :call).size
  end
end
