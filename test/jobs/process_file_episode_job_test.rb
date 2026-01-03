# frozen_string_literal: true

require "test_helper"

class ProcessFileEpisodeJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @episode = episodes(:one)
    @long_content = "# Test markdown\n\n" + ("Content here for testing. " * 10)
    @episode.update!(source_type: :file, source_text: @long_content)
    Mocktail.replace(ProcessFileEpisode)
  end

  teardown do
    Mocktail.reset
  end

  test "calls ProcessFileEpisode with episode" do
    stubs { |m| ProcessFileEpisode.call(episode: m.any) }.with { nil }

    ProcessFileEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)

    assert_equal 1, Mocktail.calls(ProcessFileEpisode, :call).size
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessFileEpisodeJob) do
      ProcessFileEpisodeJob.perform_later(episode_id: @episode.id, user_id: @user.id)
    end
  end
end
