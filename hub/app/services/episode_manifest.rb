# Duplicated from lib/episode_manifest.rb
# See braindump.md for de-duplication plan
class EpisodeManifest
  attr_reader :episodes

  def initialize(gcs_uploader)
    @gcs_uploader = gcs_uploader
    @episodes = []
  end

  def load
    content = @gcs_uploader.download_file(remote_path: "manifest.json")
    data = JSON.parse(content)
    @episodes = data["episodes"] || []
  rescue StandardError
    @episodes = []
  end

  def remove_episode(episode_id)
    @episodes.reject! { |ep| ep["id"] == episode_id }
  end

  def save
    manifest_data = { "episodes" => @episodes }
    json_content = JSON.pretty_generate(manifest_data)
    @gcs_uploader.upload_content(content: json_content, remote_path: "manifest.json")
  end
end
