# frozen_string_literal: true

require "test_helper"

class EnqueueEpisodeProcessingTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @episode.update!(title: "Test Title", author: "Test Author", description: "Test desc")
    Mocktail.replace(CloudTasksEnqueuer)
  end

  test "enqueues episode for processing via Cloud Tasks" do
    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    result = EnqueueEpisodeProcessing.call(episode: @episode, staging_path: "staging/test.txt")

    assert_equal "task-123", result
  end

  test "passes correct episode metadata" do
    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    EnqueueEpisodeProcessing.call(episode: @episode, staging_path: "staging/test.txt")

    expected_metadata = { title: "Test Title", author: "Test Author", description: "Test desc" }
    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: @episode.id, podcast_id: @episode.podcast.podcast_id, staging_path: "staging/test.txt", metadata: expected_metadata, voice_name: m.any) }
  end

  test "passes episode voice" do
    mock_tasks = Mocktail.of(CloudTasksEnqueuer)
    stubs { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: m.any) }.with { "task-123" }
    stubs { CloudTasksEnqueuer.new }.with { mock_tasks }

    EnqueueEpisodeProcessing.call(episode: @episode, staging_path: "staging/test.txt")

    verify { |m| mock_tasks.enqueue_episode_processing(episode_id: m.any, podcast_id: m.any, staging_path: m.any, metadata: m.any, voice_name: @episode.voice) }
  end
end
