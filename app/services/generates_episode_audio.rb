# frozen_string_literal: true

require "tempfile"
require "mp3info"

class GeneratesEpisodeAudio
  include EpisodeLogging

  def self.call(episode:, skip_feed_upload: false, voice_override: nil)
    new(episode: episode, skip_feed_upload: skip_feed_upload, voice_override: voice_override).call
  end

  def initialize(episode:, skip_feed_upload: false, voice_override: nil)
    @episode = episode
    @skip_feed_upload = skip_feed_upload
    @voice_override = voice_override
    @uploaded_audio_path = nil
  end

  def call
    log_info "generate_episode_audio_started"

    @episode.update!(status: :processing, processing_started_at: Time.current)

    log_info "synthesizing_audio", voice: voice_name, text_bytes: content_text.bytesize
    audio_content = synthesize_audio
    record_tts_usage

    gcs_episode_id = generate_episode_id
    log_info "uploading_audio", gcs_episode_id: gcs_episode_id, audio_bytes: audio_content.bytesize
    upload_audio(audio_content, gcs_episode_id)

    log_info "calculating_duration"
    duration_seconds = calculate_duration(audio_content)

    log_info "updating_episode", duration_seconds: duration_seconds
    @episode.update!(
      status: :complete,
      voice: voice_name,
      gcs_episode_id: gcs_episode_id,
      audio_size_bytes: audio_content.bytesize,
      duration_seconds: duration_seconds,
      processing_completed_at: Time.current
    )

    recalculate_processing_estimate

    unless @skip_feed_upload
      log_info "uploading_feed"
      upload_feed
    end

    log_info "generate_episode_audio_completed", gcs_episode_id: gcs_episode_id

    log_info "notifying_user"
    notify_user
  rescue StandardError => e
    log_error "generate_episode_audio_failed", error: e.class, message: e.message, exception: e
    cleanup_orphaned_audio
    if TransientAudioErrors.transient?(e)
      raise
    else
      @episode.update!(status: :failed, error_message: e.message)
      # Permanent failure at the synthesis layer bypasses EpisodeErrorHandling
      # (this service doesn't include the concern). Refund here so users
      # aren't short a payment/credit/slot after a TTS-layer failure.
      # Transient errors re-raise above for job retry and MUST NOT refund
      # here; retry exhaustion handles that in the job.
      # The `saved_change_to_status?` gate matches the other call sites —
      # protects the free-tier counter from double-decrement if the episode
      # was already :failed when we got here.
      RefundsPayment.call(content: @episode) if @episode.saved_change_to_status?
    end
  end

  private

  attr_reader :episode

  def synthesize_audio
    config = Tts::Config.new(voice_name: voice_name)
    @synthesizer = SynthesizesAudio.new(config: config)
    @synthesizer.call(text: content_text, voice: voice_name)
  end

  def record_tts_usage
    billed = @synthesizer&.last_billed_characters
    return unless billed&.positive?

    RecordsTtsUsage.call(
      usable: @episode,
      voice_id: voice_name,
      character_count: billed
    )
  rescue StandardError => e
    # Usage tracking is best-effort — never let accounting break audio generation.
    # Log at error level with enough context to reconstruct the missed row.
    log_error "tts_usage_record_failed",
              usable_type: @episode.class.name,
              usable_id: @episode.id,
              voice_id: voice_name,
              character_count: billed,
              error: e.class,
              message: e.message,
              exception: e
  end

  def voice_name
    @voice_name ||= @voice_override.presence || @episode.effective_voice
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
    log_warn "duration_calculation_failed", error: e.message
    nil
  end

  def upload_feed
    feed_xml = GeneratesRssFeed.call(podcast: @episode.podcast)
    cloud_storage.upload_content(content: feed_xml, remote_path: "feed.xml")
  end

  def cloud_storage
    @cloud_storage ||= CloudStorage.new(podcast_id: @episode.podcast.podcast_id)
  end

  def notify_user
    NotifiesEpisodeCompletion.call(episode: @episode) if @episode.user&.email_address.present?
  rescue StandardError => e
    log_warn "notification_failed", error: e.message
  end

  def recalculate_processing_estimate
    log_info "recalculating_processing_estimate"
    RecalculatesProcessingEstimate.call
  rescue StandardError => e
    log_warn "recalculate_processing_estimate_failed", error: e.message
  end

  def cleanup_orphaned_audio
    return unless @uploaded_audio_path

    log_info "cleaning_up_orphaned_audio", path: @uploaded_audio_path
    cloud_storage.delete_file(remote_path: @uploaded_audio_path)
  rescue StandardError => e
    log_warn "cleanup_failed", error: e.message
  end
end
