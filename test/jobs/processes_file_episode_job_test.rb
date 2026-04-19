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

  test "marks episode failed and skips processing when user is soft-deleted" do
    stubs { |m| ProcessesFileEpisode.call(episode: m.any) }.with { nil }
    @user.update!(deleted_at: Time.current)
    @episode.reload

    logs = capture_logs do
      ProcessesFileEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)
    end

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Account was deleted", @episode.error_message
    assert_match(/event=processes_file_episode_job_skipped .*reason=user_missing_or_soft_deleted/, logs)
    assert_equal 0, Mocktail.calls(ProcessesFileEpisode, :call).size
  end

  private

  def capture_logs
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    yield
    output.string
  ensure
    Rails.logger = original_logger
  end
end
