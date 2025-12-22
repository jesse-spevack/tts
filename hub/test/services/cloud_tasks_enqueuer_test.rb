require "test_helper"
require "minitest/mock"
require "ostruct"

class CloudTasksEnqueuerTest < ActiveSupport::TestCase
  test "includes voice_name in task payload" do
    captured_task = nil

    mock_client = Object.new
    mock_client.define_singleton_method(:queue_path) { |**_args| "projects/test/locations/us/queues/test" }
    mock_client.define_singleton_method(:create_task) do |parent:, task:|
      captured_task = task
      OpenStruct.new(name: "task-123")
    end

    ENV["GOOGLE_CLOUD_PROJECT"] = "test-project"
    ENV["CLOUD_TASKS_LOCATION"] = "us-central1"
    ENV["CLOUD_TASKS_QUEUE"] = "test-queue"
    ENV["GENERATOR_SERVICE_URL"] = "http://test.example.com"
    ENV["SERVICE_ACCOUNT_EMAIL"] = "test@example.com"

    Google::Cloud::Tasks.stub :cloud_tasks, mock_client do
      enqueuer = CloudTasksEnqueuer.new
      enqueuer.enqueue_episode_processing(
        episode_id: 1,
        podcast_id: "podcast_abc123",
        staging_path: "staging/file.md",
        metadata: { title: "Test", author: "Author", description: "Desc" },
        voice_name: "en-GB-Standard-D"
      )
    end

    body = JSON.parse(captured_task[:http_request][:body])
    assert_equal "en-GB-Standard-D", body["voice_name"]
  end
end
