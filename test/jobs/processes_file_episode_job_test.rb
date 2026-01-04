# frozen_string_literal: true

require "test_helper"

class ProcessesFileEpisodeJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @episode = episodes(:one)
    @long_content = "# Test markdown\n\n" + ("Content here for testing. " * 10)
    @episode.update!(source_type: :file, source_text: @long_content)
    Mocktail.replace(ProcessesFileEpisode)
  end

  teardown do
    Mocktail.reset
  end

  test "calls ProcessesFileEpisode with episode" do
    stubs { |m| ProcessesFileEpisode.call(episode: m.any) }.with { nil }

    ProcessesFileEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)

    assert_equal 1, Mocktail.calls(ProcessesFileEpisode, :call).size
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
      ProcessesFileEpisodeJob.perform_later(episode_id: @episode.id, user_id: @user.id)
    end
  end
end
