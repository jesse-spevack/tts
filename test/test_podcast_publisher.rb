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

    # Create temp MP3 file
    @temp_file = Tempfile.new(["episode", ".mp3"])
    @temp_file.write("fake mp3 content")
    @temp_file.close
  end

  def teardown
    @temp_file&.unlink
  end

  def test_publish_uploads_mp3_to_gcs
    metadata = { "title" => "Test Episode", "description" => "Test" }

    @publisher.publish(@temp_file.path, metadata)

    assert @mock_uploader.uploaded_file
    assert_equal @temp_file.path, @mock_uploader.uploaded_local_path
    assert_match(%r{episodes/\d{8}-\d{6}-test-episode\.mp3}, @mock_uploader.uploaded_remote_path)
  end

  def test_publish_adds_episode_to_manifest
    metadata = { "title" => "Test Episode", "description" => "Test" }

    @publisher.publish(@temp_file.path, metadata)

    assert @mock_manifest.episode_added
    assert_equal "Test Episode", @mock_manifest.added_episode["title"]
    assert_equal "Test", @mock_manifest.added_episode["description"]
  end

  def test_publish_generates_and_uploads_rss_feed
    metadata = { "title" => "Test Episode", "description" => "Test" }

    @publisher.publish(@temp_file.path, metadata)

    assert @mock_uploader.uploaded_content
    assert_equal "feed.xml", @mock_uploader.uploaded_content_remote_path
    assert_includes @mock_uploader.uploaded_content_data, "<?xml"
  end

  def test_publish_returns_feed_url
    metadata = { "title" => "Test Episode", "description" => "Test" }

    feed_url = @publisher.publish(@temp_file.path, metadata)

    assert_equal "https://storage.googleapis.com/test-bucket/feed.xml", feed_url
  end
end

# Mock GCS Uploader
class MockGCSUploaderForPublisher
  attr_reader :uploaded_file, :uploaded_local_path, :uploaded_remote_path, :uploaded_content,
              :uploaded_content_remote_path, :uploaded_content_data, :bucket_name

  def initialize
    @bucket_name = "test-bucket"
    @uploaded_file = false
    @uploaded_content = false
  end

  def upload_file(local_path:, remote_path:)
    @uploaded_file = true
    @uploaded_local_path = local_path
    @uploaded_remote_path = remote_path
    "https://storage.googleapis.com/test-bucket/#{remote_path}"
  end

  def upload_content(content:, remote_path:)
    @uploaded_content = true
    @uploaded_content_data = content
    @uploaded_content_remote_path = remote_path
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
