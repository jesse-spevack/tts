# frozen_string_literal: true

require "test_helper"

class ProcessesPasteEpisodeJobTest < ActiveSupport::TestCase
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

    Mocktail.replace(ProcessesPasteEpisode)
  end

  test "calls ProcessesPasteEpisode with episode" do
    stubs { |m| ProcessesPasteEpisode.call(episode: m.any) }.with { true }

    ProcessesPasteEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)

    verify { ProcessesPasteEpisode.call(episode: @episode) }
    assert true
  end

  test "can be enqueued" do
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      ProcessesPasteEpisodeJob.perform_later(episode_id: @episode.id, user_id: @user.id)
    end
  end

  test "marks episode failed and skips processing when user is soft-deleted" do
    stubs { |m| ProcessesPasteEpisode.call(episode: m.any) }.with { true }
    @user.update!(deleted_at: Time.current)
    @episode.reload

    logs = capture_logs do
      ProcessesPasteEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)
    end

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Account was deleted", @episode.error_message
    assert_match(/event=processes_paste_episode_job_skipped .*reason=user_missing_or_soft_deleted/, logs)
    assert_equal 0, Mocktail.calls(ProcessesPasteEpisode, :call).size
  end

  teardown do
    Mocktail.reset
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
