# frozen_string_literal: true

require "test_helper"

class UploadAndEnqueueEpisodeTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @plain_text_content = "Test Content\n\nThis is test content."

    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    Mocktail.replace(GcsUploader)
    Mocktail.replace(CloudTasksEnqueuer)
  end

  test "uploads plain text to staging and enqueues processing" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    UploadAndEnqueueEpisode.call(episode: @episode, content: @plain_text_content)

    verify { |m| mock_gcs.upload_staging_file(content: @plain_text_content, filename: m.any) }
    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: @episode.id, podcast_id: m.any, staging_path: "staging/test.txt", metadata: m.any, voice_name: m.any) }
    assert true
  end

  test "passes episode.voice to enqueue_episode_processing" do
    @episode.user.voice_preference = "sloane"

    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    UploadAndEnqueueEpisode.call(episode: @episode, content: @plain_text_content)

    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: "en-US-Standard-C") }
    assert true
  end
end
