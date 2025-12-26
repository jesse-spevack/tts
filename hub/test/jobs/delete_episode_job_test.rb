# frozen_string_literal: true

require "test_helper"

class DeleteEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:complete)
    Mocktail.replace(DeleteEpisode)
  end

  test "calls DeleteEpisode service" do
    stubs { |m| DeleteEpisode.call(episode: m.any) }.with { nil }

    DeleteEpisodeJob.perform_now(@episode)

    assert_equal 1, Mocktail.calls(DeleteEpisode, :call).size
  end
end
