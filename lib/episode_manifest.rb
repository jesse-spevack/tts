require "json"
require "time"

class EpisodeManifest
  attr_reader :episodes

  # Initialize episode manifest with GCS uploader
  # @param gcs_uploader [GCSUploader] Instance of GCSUploader
  def initialize(gcs_uploader)
    @gcs_uploader = gcs_uploader
    @episodes = []
  end

  # Load manifest from GCS or initialize empty array if doesn't exist
  # @return [Array] Array of episode hashes
  def load
    begin
      content = @gcs_uploader.download_file(remote_path: "manifest.json")
      data = JSON.parse(content)
      @episodes = data["episodes"] || []
    rescue StandardError
      # If manifest doesn't exist or error occurs, start with empty array
      @episodes = []
    end

    @episodes
  end

  # Add new episode to manifest and sort by published_at (newest first)
  # @param episode_data [Hash] Episode metadata hash
  def add_episode(episode_data)
    @episodes << episode_data
    @episodes.sort_by! { |ep| Time.parse(ep["published_at"]) }.reverse!
  end

  # Save manifest to GCS
  def save
    manifest_data = { "episodes" => @episodes }
    json_content = JSON.pretty_generate(manifest_data)
    @gcs_uploader.upload_content(content: json_content, remote_path: "manifest.json")
  end

  # Generate unique episode GUID from timestamp and title slug
  # @param title [String] Episode title
  # @return [String] Unique GUID (format: YYYYMMDD-HHMMSS-title-slug)
  def self.generate_guid(title)
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    slug = title.downcase
               .gsub(/[^a-z0-9\s-]/, "") # Remove special characters
               .gsub(/\s+/, "-")          # Replace spaces with hyphens
               .gsub(/-+/, "-")           # Collapse multiple hyphens
               .strip

    "#{timestamp}-#{slug}"
  end
end
