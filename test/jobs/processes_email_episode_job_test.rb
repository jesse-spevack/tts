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

    verify { |_m| ProcessesEmailEpisode.call(episode: @episode) }
    assert true
  end

  test "job is queued on default queue" do
    assert_equal "default", ProcessesEmailEpisodeJob.new.queue_name
  end

  test "marks episode failed and skips processing when user is soft-deleted" do
    stubs { |m| ProcessesEmailEpisode.call(episode: m.any) }.with { true }
    @user.update!(deleted_at: Time.current)
    @episode.reload

    logs = capture_logs do
      ProcessesEmailEpisodeJob.perform_now(episode_id: @episode.id, user_id: @user.id)
    end

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "Account was deleted", @episode.error_message
    assert_match(/event=processes_email_episode_job_skipped .*reason=user_missing_or_soft_deleted/, logs)
    assert_equal 0, Mocktail.calls(ProcessesEmailEpisode, :call).size
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
