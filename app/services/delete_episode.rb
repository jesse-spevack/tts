# frozen_string_literal: true

class DeleteEpisode
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    Rails.logger.info "event=delete_episode_started episode_id=#{@episode.id}"

    soft_delete_episode
    delete_audio_file
    regenerate_feed

    Rails.logger.info "event=delete_episode_completed episode_id=#{@episode.id}"
  end

  private

  def soft_delete_episode
    @episode.update!(deleted_at: Time.current) unless @episode.soft_deleted?
    Rails.logger.info "event=episode_soft_deleted episode_id=#{@episode.id}"
  end

  def delete_audio_file
    return unless @episode.gcs_episode_id.present?

    cloud_storage.delete_file(remote_path: "episodes/#{@episode.gcs_episode_id}.mp3")
    Rails.logger.info "event=audio_file_deleted episode_id=#{@episode.id} gcs_episode_id=#{@episode.gcs_episode_id}"
  rescue StandardError => e
    Rails.logger.warn "event=audio_delete_failed episode_id=#{@episode.id} error=#{e.message}"
  end

  def regenerate_feed
    feed_xml = GenerateRssFeed.call(podcast: @episode.podcast)
    cloud_storage.upload_content(content: feed_xml, remote_path: "feed.xml")
    Rails.logger.info "event=feed_regenerated podcast_id=#{@episode.podcast.podcast_id}"
  end

  def cloud_storage
    @cloud_storage ||= CloudStorage.new(podcast_id: @episode.podcast.podcast_id)
  end
end
