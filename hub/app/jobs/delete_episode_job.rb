class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(podcast_id:, gcs_episode_id:)
    Rails.logger.info "event=delete_episode_job_started podcast_id=#{podcast_id} gcs_episode_id=#{gcs_episode_id}"

    gcs = GcsUploader.new(podcast_id: podcast_id)

    deleted = gcs.delete_file(remote_path: "episodes/#{gcs_episode_id}.mp3")
    Rails.logger.info "event=delete_episode_mp3_deleted podcast_id=#{podcast_id} gcs_episode_id=#{gcs_episode_id} deleted=#{deleted}"

    manifest = EpisodeManifest.new(gcs)
    manifest.load
    manifest.remove_episode(gcs_episode_id)
    manifest.save
    Rails.logger.info "event=delete_episode_manifest_updated podcast_id=#{podcast_id} gcs_episode_id=#{gcs_episode_id} remaining_episodes=#{manifest.episodes.size}"

    podcast_config = YAML.load_file(Rails.root.join("config/podcast.yml"))
    feed_xml = RssGenerator.new(podcast_config, manifest.episodes).generate
    gcs.upload_content(content: feed_xml, remote_path: "feed.xml")

    Rails.logger.info "event=delete_episode_job_completed podcast_id=#{podcast_id} gcs_episode_id=#{gcs_episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=delete_episode_job_failed podcast_id=#{podcast_id} gcs_episode_id=#{gcs_episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
