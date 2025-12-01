# frozen_string_literal: true

require "test_helper"

class UploadAndEnqueueEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @content = "# Test Content\n\nThis is test content."

    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    Mocktail.replace(GcsUploader)
    Mocktail.replace(CloudTasksEnqueuer)
  end

  test "uploads content to staging and enqueues processing" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.md" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    UploadAndEnqueueEpisode.call(episode: @episode, content: @content)

    verify { |m| mock_gcs.upload_staging_file(content: @content, filename: m.any) }
    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: @episode.id, podcast_id: m.any, staging_path: "staging/test.md", metadata: m.any, voice_name: m.any) }
  end
end
