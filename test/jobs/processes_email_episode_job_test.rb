# frozen_string_literal: true

require "test_helper"

class ProcessesEmailEpisodeJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @episode = Episode.create!(
      podcast: @podcast,
      user: @user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing email content...",
      source_type: :email,
      source_text: "A" * 150,
      status: :processing
    )

    Mocktail.replace(ProcessesEmailEpisode)
  end

  test "calls ProcessesEmailEpisode with episode" do
    stubs { |m| ProcessesEmailEpisode.call(episode: m.any) }.with { true }

    ProcessesEmailEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)

    verify { |m| ProcessesEmailEpisode.call(episode: @episode) }
    assert true
  end

  test "job is queued on default queue" do
    assert_equal "default", ProcessesEmailEpisodeJob.new.queue_name
  end

  teardown do
    Mocktail.reset
  end
end
