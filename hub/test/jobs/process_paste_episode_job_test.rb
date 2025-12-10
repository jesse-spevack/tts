# frozen_string_literal: true

require "test_helper"

class ProcessPasteEpisodeJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: "Test content for processing",
      status: :processing
    )

    Mocktail.replace(ProcessPasteEpisode)
  end

  test "calls ProcessPasteEpisode with episode" do
    stubs { |m| ProcessPasteEpisode.call(episode: m.any) }.with { true }

    ProcessPasteEpisodeJob.perform_now(@episode.id)

    verify { ProcessPasteEpisode.call(episode: @episode) }
  end

  teardown do
    Mocktail.reset
  end
end
