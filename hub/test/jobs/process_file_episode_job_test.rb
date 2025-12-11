# frozen_string_literal: true

require "test_helper"

class ProcessFileEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(source_type: :file, source_text: "# Test markdown")
    Mocktail.replace(ProcessFileEpisode)
  end

  test "calls ProcessFileEpisode with episode" do
    stubs { |m| ProcessFileEpisode.call(episode: m.any) }.with { nil }

    ProcessFileEpisodeJob.perform_now(@episode.id)

    verify { ProcessFileEpisode.call(episode: @episode) }
  end
end
