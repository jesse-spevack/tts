# frozen_string_literal: true

require "tempfile"
require "mp3info"

class GenerateEpisodeAudio
  def self.call(episode:, skip_feed_upload: false)
    new(episode: episode, skip_feed_upload: skip_feed_upload).call
  end

  def initialize(episode:, skip_feed_upload: false)
    @episode = episode
    @skip_feed_upload = skip_feed_upload
    @uploaded_audio_path = nil
  end

  def call
    Rails.logger.info "event=generate_episode_audio_started episode_id=#{@episode.id}"

    @episode.update!(status: "processing")

    Rails.logger.info "event=synthesizing_audio episode_id=#{@episode.id} voice=#{voice_name} text_bytes=#{content_text.bytesize}"
    audio_content = synthesize_audio

    gcs_episode_id = generate_episode_id
    Rails.logger.info "event=uploading_audio episode_id=#{@episode.id} gcs_episode_id=#{gcs_episode_id} audio_bytes=#{audio_content.bytesize}"
    upload_audio(audio_content, gcs_episode_id)

    Rails.logger.info "event=calculating_duration episode_id=#{@episode.id}"
    duration_seconds = calculate_duration(audio_content)

    Rails.logger.info "event=updating_episode episode_id=#{@episode.id} duration_seconds=#{duration_seconds}"
    @episode.update!(
      status: "complete",
      gcs_episode_id: gcs_episode_id,
      audio_size_bytes: audio_content.bytesize,
      duration_seconds: duration_seconds
    )

    unless @skip_feed_upload
      Rails.logger.info "event=uploading_feed episode_id=#{@episode.id}"
      upload_feed
    end

    Rails.logger.info "event=generate_episode_audio_completed episode_id=#{@episode.id} gcs_episode_id=#{gcs_episode_id}"

    Rails.logger.info "event=notifying_user episode_id=#{@episode.id}"
    notify_user
  rescue StandardError => e
    Rails.logger.error "event=generate_episode_audio_failed episode_id=#{@episode.id} error=#{e.class} message=#{e.message}"
    cleanup_orphaned_audio
    @episode.update!(status: "failed", error_message: e.message)
  end

  private

  def synthesize_audio
    config = Tts::Config.new(voice_name: voice_name)
    synthesizer = Tts::Synthesizer.new(config: config)
    synthesizer.synthesize(content_text, voice: voice_name)
  end

  def voice_name
    @episode.voice
  end

  def content_text
    @episode.source_text || ""
  end

  def generate_episode_id
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    slug = @episode.title.downcase
                   .gsub(/[^a-z0-9\s-]/, "")
                   .gsub(/\s+/, "-")
                   .gsub(/-+/, "-")
                   .strip
    "#{timestamp}-#{slug}"
  end

  def upload_audio(audio_content, gcs_episode_id)
    @uploaded_audio_path = "episodes/#{gcs_episode_id}.mp3"
    cloud_storage.upload_content(
      content: audio_content,
      remote_path: @uploaded_audio_path
    )
  end

  def calculate_duration(audio_content)
    Tempfile.create([ "episode", ".mp3" ]) do |temp_file|
      temp_file.binmode
      temp_file.write(audio_content)
      temp_file.close
      Mp3Info.open(temp_file.path) { |mp3| mp3.length.round }
    end
  rescue StandardError => e
    Rails.logger.warn "event=duration_calculation_failed error=#{e.message}"
    nil
  end

  def upload_feed
    feed_xml = GenerateRssFeed.call(podcast: @episode.podcast)
    cloud_storage.upload_content(content: feed_xml, remote_path: "feed.xml")
  end

  def cloud_storage
    @cloud_storage ||= CloudStorage.new(podcast_id: @episode.podcast.podcast_id)
  end

  def notify_user
    NotifiesEpisodeCompletion.call(episode: @episode) if @episode.user&.email_address.present?
  rescue StandardError => e
    Rails.logger.warn "event=notification_failed episode_id=#{@episode.id} error=#{e.message}"
  end

  def cleanup_orphaned_audio
    return unless @uploaded_audio_path

    Rails.logger.info "event=cleaning_up_orphaned_audio episode_id=#{@episode.id} path=#{@uploaded_audio_path}"
    cloud_storage.delete_file(remote_path: @uploaded_audio_path)
  rescue StandardError => e
    Rails.logger.warn "event=cleanup_failed episode_id=#{@episode.id} error=#{e.message}"
  end
end
