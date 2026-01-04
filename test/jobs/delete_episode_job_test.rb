# frozen_string_literal: true

require "test_helper"

class DeleteEpisodeJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @episode = episodes(:one)
    Mocktail.replace(DeletesEpisode)
  end

  test "calls DeletesEpisode with episode" do
    stubs { |m| DeletesEpisode.call(episode: m.any) }.with { true }

    DeleteEpisodeJob.perform_now(episode_id: @episode.id)

    verify { DeletesEpisode.call(episode: @episode) }
    assert true
  end

  test "can be enqueued" do
    assert_enqueued_with(job: DeleteEpisodeJob) do
      DeleteEpisodeJob.perform_later(episode_id: @episode.id)
    end
  end

  teardown do
    Mocktail.reset
  end
end
