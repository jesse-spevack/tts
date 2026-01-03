# frozen_string_literal: true

require "test_helper"

class ProcessPasteEpisodeJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @long_content = "A" * 150
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: @long_content,
      status: :processing
    )

    Mocktail.replace(ProcessPasteEpisode)
  end

  test "calls ProcessPasteEpisode with episode" do
    stubs { |m| ProcessPasteEpisode.call(episode: m.any) }.with { true }

    ProcessPasteEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)

    verify { ProcessPasteEpisode.call(episode: @episode) }
    assert true
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      ProcessPasteEpisodeJob.perform_later(episode_id: @episode.id, user_id: @user.id)
    end
  end

  teardown do
    Mocktail.reset
  end
end
