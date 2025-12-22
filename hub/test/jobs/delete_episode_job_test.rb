require "test_helper"

class DeleteEpisodeJobTest < ActiveJob::TestCase
  setup do
    Mocktail.replace(GcsUploader)
    Mocktail.replace(EpisodeManifest)
    Mocktail.replace(RssGenerator)
  end

  test "deletes MP3 from GCS" do
    mock_gcs = Mocktail.of(GcsUploader)
    mock_manifest = Mocktail.of(EpisodeManifest)
    mock_rss = Mocktail.of(RssGenerator)

    stubs { GcsUploader.new(podcast_id: "pod1") }.with { mock_gcs }
    stubs { EpisodeManifest.new(mock_gcs) }.with { mock_manifest }
    stubs { mock_manifest.load }.with { [] }
    stubs { |m| mock_manifest.remove_episode(m.any) }.with { nil }
    stubs { mock_manifest.save }.with { nil }
    stubs { mock_manifest.episodes }.with { [] }
    stubs { |m| RssGenerator.new(m.any, m.any) }.with { mock_rss }
    stubs { mock_rss.generate }.with { "<rss></rss>" }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }

    DeleteEpisodeJob.perform_now(podcast_id: "pod1", gcs_episode_id: "test-episode")

    verify { mock_gcs.delete_file(remote_path: "episodes/test-episode.mp3") }
  end

  test "removes episode from manifest and saves" do
    mock_gcs = Mocktail.of(GcsUploader)
    mock_manifest = Mocktail.of(EpisodeManifest)
    mock_rss = Mocktail.of(RssGenerator)

    stubs { GcsUploader.new(podcast_id: "pod1") }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { nil }
    stubs { EpisodeManifest.new(mock_gcs) }.with { mock_manifest }
    stubs { mock_manifest.load }.with { [] }
    stubs { mock_manifest.episodes }.with { [] }
    stubs { |m| RssGenerator.new(m.any, m.any) }.with { mock_rss }
    stubs { mock_rss.generate }.with { "<rss></rss>" }
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }

    DeleteEpisodeJob.perform_now(podcast_id: "pod1", gcs_episode_id: "test-episode")

    verify { mock_manifest.remove_episode("test-episode") }
    verify { mock_manifest.save }
  end

  test "regenerates and uploads feed.xml" do
    mock_gcs = Mocktail.of(GcsUploader)
    mock_manifest = Mocktail.of(EpisodeManifest)
    mock_rss = Mocktail.of(RssGenerator)

    stubs { GcsUploader.new(podcast_id: "pod1") }.with { mock_gcs }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { nil }
    stubs { EpisodeManifest.new(mock_gcs) }.with { mock_manifest }
    stubs { mock_manifest.load }.with { [] }
    stubs { |m| mock_manifest.remove_episode(m.any) }.with { nil }
    stubs { mock_manifest.save }.with { nil }
    stubs { mock_manifest.episodes }.with { [] }
    stubs { |m| RssGenerator.new(m.any, []) }.with { mock_rss }
    stubs { mock_rss.generate }.with { "<rss>feed content</rss>" }

    DeleteEpisodeJob.perform_now(podcast_id: "pod1", gcs_episode_id: "test-episode")

    verify { mock_gcs.upload_content(content: "<rss>feed content</rss>", remote_path: "feed.xml") }
  end
end
