require "minitest/autorun"
require "json"
require_relative "../lib/episode_manifest"

class TestEpisodeManifest < Minitest::Test
  def setup
    @mock_uploader = MockGCSUploader.new
    @manifest = EpisodeManifest.new(@mock_uploader)
  end

  def test_initializes_with_gcs_uploader
    assert_instance_of EpisodeManifest, @manifest
  end

  def test_load_returns_empty_array_when_manifest_does_not_exist
    @mock_uploader.manifest_exists = false
    episodes = @manifest.load

    assert_equal [], episodes
  end

  def test_load_returns_episodes_from_gcs
    @mock_uploader.manifest_exists = true
    @mock_uploader.manifest_content = {
      "episodes" => [
        {
          "id" => "20251026-episode-1",
          "title" => "First Episode",
          "description" => "First description",
          "published_at" => "2025-10-26T10:00:00Z"
        }
      ]
    }.to_json

    episodes = @manifest.load

    assert_equal 1, episodes.length
    assert_equal "First Episode", episodes[0]["title"]
  end

  def test_add_episode_appends_to_episodes
    episode_data = {
      "id" => "20251026-new-episode",
      "title" => "New Episode",
      "description" => "New description",
      "mp3_url" => "https://example.com/episode.mp3",
      "file_size_bytes" => 1024,
      "published_at" => "2025-10-26T12:00:00Z",
      "guid" => "20251026-new-episode"
    }

    @manifest.load
    @manifest.add_episode(episode_data)

    assert_equal 1, @manifest.episodes.length
    assert_equal "New Episode", @manifest.episodes[0]["title"]
  end

  def test_add_episode_sorts_by_published_at_newest_first
    @mock_uploader.manifest_exists = true
    @mock_uploader.manifest_content = {
      "episodes" => [
        {
          "id" => "20251026-old",
          "title" => "Old Episode",
          "published_at" => "2025-10-26T10:00:00Z"
        }
      ]
    }.to_json

    @manifest.load

    new_episode = {
      "id" => "20251027-new",
      "title" => "New Episode",
      "published_at" => "2025-10-27T10:00:00Z"
    }

    @manifest.add_episode(new_episode)

    # Newest should be first
    assert_equal "New Episode", @manifest.episodes[0]["title"]
    assert_equal "Old Episode", @manifest.episodes[1]["title"]
  end

  def test_save_uploads_manifest_to_gcs
    episode_data = {
      "id" => "20251026-test",
      "title" => "Test Episode",
      "published_at" => "2025-10-26T12:00:00Z"
    }

    @manifest.load
    @manifest.add_episode(episode_data)
    @manifest.save

    assert @mock_uploader.uploaded
    assert_equal "manifest.json", @mock_uploader.uploaded_remote_path

    uploaded_data = JSON.parse(@mock_uploader.uploaded_content)
    assert_equal 1, uploaded_data["episodes"].length
    assert_equal "Test Episode", uploaded_data["episodes"][0]["title"]
  end

  def test_generate_guid_creates_unique_id
    guid1 = EpisodeManifest.generate_guid("My Episode Title")
    guid2 = EpisodeManifest.generate_guid("Another Episode")

    assert_match(/^\d{8}-\d{6}-/, guid1)
    assert_match(/^\d{8}-\d{6}-/, guid2)
    refute_equal guid1, guid2
  end

  def test_generate_guid_creates_url_safe_slug
    guid = EpisodeManifest.generate_guid("My Cool Episode! @#$%")

    assert_includes guid, "my-cool-episode"
    refute_includes guid, "!"
    refute_includes guid, "@"
    refute_includes guid, "$"
  end

  def test_episodes_accessor_returns_episodes_array
    @manifest.load
    assert_equal [], @manifest.episodes

    @manifest.add_episode({ "id" => "test", "title" => "Test", "published_at" => "2025-10-26T10:00:00Z" })
    assert_equal 1, @manifest.episodes.length
  end
end

# Mock GCS Uploader for testing
class MockGCSUploader
  attr_accessor :manifest_exists, :manifest_content, :uploaded, :uploaded_remote_path, :uploaded_content

  def initialize
    @manifest_exists = false
    @manifest_content = nil
    @uploaded = false
    @uploaded_remote_path = nil
    @uploaded_content = nil
  end

  def download_file(remote_path:)
    raise "File not found" unless @manifest_exists
    @manifest_content
  end

  def upload_content(content:, remote_path:)
    @uploaded = true
    @uploaded_remote_path = remote_path
    @uploaded_content = content
  end
end
