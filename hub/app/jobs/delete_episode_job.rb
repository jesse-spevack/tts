class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(podcast_id:, gcs_episode_id:)
    gcs = GcsUploader.new(podcast_id: podcast_id)

    # Delete MP3
    gcs.delete_file(remote_path: "episodes/#{gcs_episode_id}.mp3")

    # Update manifest
    manifest = EpisodeManifest.new(gcs)
    manifest.load
    manifest.remove_episode(gcs_episode_id)
    manifest.save

    # Regenerate feed
    podcast_config = YAML.load_file(Rails.root.join("../config/podcast.yml"))
    feed_xml = RssGenerator.new(podcast_config, manifest.episodes).generate
    gcs.upload_content(content: feed_xml, remote_path: "feed.xml")
  end
end
