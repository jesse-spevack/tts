# frozen_string_literal: true

require "test_helper"

class DeleteEpisodeJobTest < ActiveJob::TestCase
  setup do
    @episode = episodes(:complete)
    Mocktail.replace(GcsUploader)
    Mocktail.replace(GenerateRssFeed)
  end

  test "deletes MP3 from GCS" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| GcsUploader.new(podcast_id: m.any) }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    DeleteEpisodeJob.perform_now(@episode)

    assert_equal 1, Mocktail.calls(mock_gcs, :delete_file).size
  end

  test "regenerates RSS feed from database" do
    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| GcsUploader.new(podcast_id: m.any) }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss>feed content</rss>" }

    DeleteEpisodeJob.perform_now(@episode)

    assert_equal 1, Mocktail.calls(GenerateRssFeed, :call).size
    assert_equal 1, Mocktail.calls(mock_gcs, :upload_content).size
  end

  test "skips MP3 deletion if no gcs_episode_id" do
    @episode.update!(gcs_episode_id: nil)

    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| GcsUploader.new(podcast_id: m.any) }.with { mock_gcs }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    DeleteEpisodeJob.perform_now(@episode)

    assert_equal 0, Mocktail.calls(mock_gcs, :delete_file).size
  end

  test "soft deletes episode by setting deleted_at" do
    # Clear any existing deleted_at set by controller
    @episode.update_column(:deleted_at, nil)
    assert_nil @episode.deleted_at

    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| GcsUploader.new(podcast_id: m.any) }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GenerateRssFeed.call(podcast: m.any) }.with { "<rss></rss>" }

    DeleteEpisodeJob.perform_now(@episode)

    @episode.reload
    assert_not_nil Episode.unscoped.find(@episode.id).deleted_at
  end
end
