# frozen_string_literal: true

require "test_helper"

class EpisodeJobLoggingTest < ActiveSupport::TestCase
  class TestJob < ApplicationJob
    include EpisodeJobLogging

    def perform(episode_id:, user_id:, should_fail: false)
      with_episode_logging(episode_id: episode_id, user_id: user_id) do
        raise StandardError, "Test error" if should_fail
        "success"
      end
    end
  end

  test "logs started and completed events on success" do
    logs = capture_logs do
      TestJob.perform_now(episode_id: 1, user_id: 2)
    end

    assert_match(/event=episode_job_logging_test\/test_job_started episode_id=1 user_id=2/, logs)
    assert_match(/event=episode_job_logging_test\/test_job_completed episode_id=1/, logs)
  end

  test "logs started and failed events on error" do
    logs = capture_logs do
      assert_raises(StandardError) do
        TestJob.perform_now(episode_id: 1, user_id: 2, should_fail: true)
      end
    end

    assert_match(/event=episode_job_logging_test\/test_job_started episode_id=1 user_id=2/, logs)
    assert_match(/event=episode_job_logging_test\/test_job_failed episode_id=1 error=StandardError message=Test error/, logs)
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
