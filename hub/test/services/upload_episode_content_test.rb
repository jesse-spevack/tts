# frozen_string_literal: true

require "test_helper"

class UploadEpisodeContentTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
    Mocktail.replace(GcsUploader)
  end

  test "uploads content to GCS and returns staging path" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/123-456.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    result = UploadEpisodeContent.call(episode: @episode, content: "Test content")

    assert_equal "staging/123-456.txt", result
    verify { |m| mock_gcs.upload_staging_file(content: "Test content", filename: m.any) }
  end

  test "generates filename with episode id and timestamp" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    UploadEpisodeContent.call(episode: @episode, content: "Test content")

    verify { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.that { |f| f.start_with?("#{@episode.id}-") && f.end_with?(".txt") }) }
  end

  test "initializes GcsUploader with bucket and podcast_id" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_staging_file(content: m.any, filename: m.any) }.with { "staging/test.txt" }
    stubs { |m| GcsUploader.new(m.any, podcast_id: m.any) }.with { mock_gcs }

    UploadEpisodeContent.call(episode: @episode, content: "Test content")

    verify { GcsUploader.new("test-bucket", podcast_id: @episode.podcast.podcast_id) }
  end
end
