require "minitest/autorun"
require "tempfile"
require_relative "../lib/podcast_publisher"

class TestPodcastPublisher < Minitest::Test
  def setup
    @podcast_config = {
      "title" => "Test Podcast",
      "author" => "Test Author"
    }
    @mock_uploader = MockGCSUploaderForPublisher.new
    @mock_manifest = MockEpisodeManifestForPublisher.new
    @publisher = PodcastPublisher.new(
      podcast_config: @podcast_config,
      gcs_uploader: @mock_uploader,
      episode_manifest: @mock_manifest
    )

    # Create fake audio content
    @audio_content = "fake mp3 content"
  end

  def test_publish_uploads_mp3_to_gcs
    metadata = { "title" => "Test Episode", "description" => "Test" }

    @publisher.publish(audio_content: @audio_content, metadata: metadata)

    mp3_upload = @mock_uploader.uploads.find { |u| u[:remote_path].include?("episodes/") }
    assert mp3_upload, "MP3 upload not found"
    assert_match(%r{episodes/\d{8}-\d{6}-test-episode\.mp3}, mp3_upload[:remote_path])
  end

  def test_publish_adds_episode_to_manifest
    metadata = { "title" => "Test Episode", "description" => "Test" }

    @publisher.publish(audio_content: @audio_content, metadata: metadata)

    assert @mock_manifest.episode_added
    assert_equal "Test Episode", @mock_manifest.added_episode["title"]
    assert_equal "Test", @mock_manifest.added_episode["description"]
  end

  def test_publish_generates_and_uploads_rss_feed
    metadata = { "title" => "Test Episode", "description" => "Test" }

    @publisher.publish(audio_content: @audio_content, metadata: metadata)

    feed_upload = @mock_uploader.uploads.find { |u| u[:remote_path] == "feed.xml" }
    assert feed_upload, "RSS feed upload not found"
    assert_includes feed_upload[:content], "<?xml"
  end

  def test_publish_returns_episode_data
    metadata = { "title" => "Test Episode", "description" => "Test" }

    episode_data = @publisher.publish(audio_content: @audio_content, metadata: metadata)

    assert_equal "Test Episode", episode_data["title"]
    assert_equal "Test", episode_data["description"]
    assert_equal @audio_content.bytesize, episode_data["file_size_bytes"]
    assert_match(/^\d{8}-\d{6}-test-episode$/, episode_data["id"])
  end
end

# Mock GCS Uploader
class MockGCSUploaderForPublisher
  attr_reader :bucket_name, :uploads

  def initialize
    @bucket_name = "test-bucket"
    @uploads = []
  end

  def upload_content(content:, remote_path:)
    @uploads << { type: :content, content: content, remote_path: remote_path }
    "https://storage.googleapis.com/test-bucket/#{remote_path}"
  end

  def get_public_url(remote_path:)
    "https://storage.googleapis.com/test-bucket/#{remote_path}"
  end
end

# Mock Episode Manifest
class MockEpisodeManifestForPublisher
  attr_reader :episode_added, :added_episode, :episodes

  def initialize
    @episodes = []
    @episode_added = false
  end

  def load
    @episodes
  end

  def add_episode(episode_data)
    @episode_added = true
    @added_episode = episode_data
    @episodes << episode_data
  end

  def save
    # no-op for mock
  end
end
