# frozen_string_literal: true

class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode)
    Rails.logger.info "event=delete_episode_started episode_id=#{episode.id}"

    soft_delete_episode(episode)
    delete_audio_file(episode)
    regenerate_feed(episode.podcast)

    Rails.logger.info "event=delete_episode_completed episode_id=#{episode.id}"
  rescue StandardError => e
    Rails.logger.error "event=delete_episode_failed episode_id=#{episode.id} error=#{e.class} message=#{e.message}"
    raise
  end

  private

  def soft_delete_episode(episode)
    episode.update!(deleted_at: Time.current) unless episode.soft_deleted?
    Rails.logger.info "event=episode_soft_deleted episode_id=#{episode.id}"
  end

  def delete_audio_file(episode)
    return unless episode.gcs_episode_id.present?

    cloud_storage(episode).delete_file(remote_path: "episodes/#{episode.gcs_episode_id}.mp3")
    Rails.logger.info "event=audio_file_deleted episode_id=#{episode.id} gcs_episode_id=#{episode.gcs_episode_id}"
  rescue StandardError => e
    Rails.logger.warn "event=audio_delete_failed episode_id=#{episode.id} error=#{e.message}"
  end

  def regenerate_feed(podcast)
    feed_xml = GenerateRssFeed.call(podcast: podcast)
    cloud_storage_for_podcast(podcast).upload_content(content: feed_xml, remote_path: "feed.xml")
    Rails.logger.info "event=feed_regenerated podcast_id=#{podcast.podcast_id}"
  end

  def cloud_storage(episode)
    CloudStorage.new(podcast_id: episode.podcast.podcast_id)
  end

  def cloud_storage_for_podcast(podcast)
    CloudStorage.new(podcast_id: podcast.podcast_id)
  end
end
