# frozen_string_literal: true

class DeleteEpisode
  include EpisodeLogging

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    log_info "delete_episode_started"

    soft_delete_episode
    delete_audio_file
    regenerate_feed

    log_info "delete_episode_completed"
  end

  private

  attr_reader :episode

  def soft_delete_episode
    @episode.update!(deleted_at: Time.current) unless @episode.soft_deleted?
    log_info "episode_soft_deleted"
  end

  def delete_audio_file
    return unless @episode.gcs_episode_id.present?

    cloud_storage.delete_file(remote_path: "episodes/#{@episode.gcs_episode_id}.mp3")
    log_info "audio_file_deleted", gcs_episode_id: @episode.gcs_episode_id
  rescue StandardError => e
    log_warn "audio_delete_failed", error: e.message
  end

  def regenerate_feed
    feed_xml = GeneratesRssFeed.call(podcast: @episode.podcast)
    cloud_storage.upload_content(content: feed_xml, remote_path: "feed.xml")
    log_info "feed_regenerated", podcast_id: @episode.podcast.podcast_id
  end

  def cloud_storage
    @cloud_storage ||= CloudStorage.new(podcast_id: @episode.podcast.podcast_id)
  end
end
