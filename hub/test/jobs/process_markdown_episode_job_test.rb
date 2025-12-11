# frozen_string_literal: true

require "test_helper"

class ProcessMarkdownEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(source_type: :markdown, source_text: "# Test markdown")
    Mocktail.replace(ProcessMarkdownEpisode)
  end

  test "calls ProcessMarkdownEpisode with episode" do
    stubs { |m| ProcessMarkdownEpisode.call(episode: m.any) }.with { nil }

    ProcessMarkdownEpisodeJob.perform_now(@episode.id)

    verify { ProcessMarkdownEpisode.call(episode: @episode) }
  end
end
