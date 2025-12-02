require "time"
require "tempfile"
require "mp3info"
require_relative "episode_manifest"
require_relative "rss_generator"

class PodcastPublisher
  # Initialize podcast publisher
  # @param podcast_config [Hash] Podcast-level configuration
  # @param gcs_uploader [GCSUploader] GCS uploader instance
  # @param episode_manifest [EpisodeManifest] Episode manifest instance
  def initialize(podcast_config:, gcs_uploader:, episode_manifest:)
    @podcast_config = podcast_config
    @gcs_uploader = gcs_uploader
    @episode_manifest = episode_manifest
  end

  # Publish episode to podcast feed
  # @param audio_content [String] MP3 audio content (binary string)
  # @param metadata [Hash] Episode metadata (title, description, author)
  # @return [Hash] Episode data including gcs_episode_id and audio_size_bytes
  def publish(audio_content:, metadata:)
    guid = EpisodeManifest.generate_guid(metadata["title"])
    mp3_url = upload_mp3(audio_content: audio_content, guid: guid)
    duration_seconds = calculate_duration(audio_content)
    episode_data = build_episode_data(
      metadata: metadata,
      guid: guid,
      mp3_url: mp3_url,
      file_size: audio_content.bytesize,
      duration_seconds: duration_seconds
    )

    update_manifest(episode_data)
    upload_rss_feed

    episode_data
  end

  private

  def upload_mp3(audio_content:, guid:)
    remote_path = "episodes/#{guid}.mp3"
    @gcs_uploader.upload_content(content: audio_content, remote_path: remote_path)
  end

  def calculate_duration(audio_content)
    Tempfile.create(["episode", ".mp3"]) do |temp_file|
      temp_file.binmode
      temp_file.write(audio_content)
      temp_file.close
      Mp3Info.open(temp_file.path) { |mp3| mp3.length.round }
    end
  end

  def build_episode_data(metadata:, guid:, mp3_url:, file_size:, duration_seconds:)
    {
      "id" => guid,
      "title" => metadata["title"],
      "description" => metadata["description"],
      "author" => metadata["author"],
      "mp3_url" => mp3_url,
      "file_size_bytes" => file_size,
      "duration_seconds" => duration_seconds,
      "published_at" => Time.now.utc.iso8601,
      "guid" => guid
    }
  end

  def update_manifest(episode_data)
    @episode_manifest.load
    @episode_manifest.add_episode(episode_data)
    @episode_manifest.save
  end

  def upload_rss_feed
    feed_url = @gcs_uploader.get_public_url(remote_path: "feed.xml")
    config_with_feed_url = @podcast_config.merge("feed_url" => feed_url)
    rss_generator = RSSGenerator.new(config_with_feed_url, @episode_manifest.episodes)
    rss_xml = rss_generator.generate
    @gcs_uploader.upload_content(content: rss_xml, remote_path: "feed.xml")
  end
end
