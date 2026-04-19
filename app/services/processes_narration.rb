# frozen_string_literal: true

require "tempfile"
require "mp3info"

class ProcessesNarration
  include StructuredLogging

  class ProcessingError < StandardError; end

  GCS_NARRATION_SCOPE = "narrations"

  def self.call(narration:)
    new(narration: narration).call
  end

  def initialize(narration:)
    @narration = narration
    @uploaded_audio_path = nil
  end

  def call
    log_info "process_narration_started", narration_id: narration.id, source_type: narration.source_type

    narration.update!(status: :preparing)
    fetch_content
    check_character_limit
    process_with_llm
    synthesize_and_upload

    log_info "process_narration_completed", narration_id: narration.id
  rescue ProcessingError => e
    fail_narration(e.message)
  rescue StandardError => e
    log_error "process_narration_error", narration_id: narration.id, error: e.class, message: e.message, exception: e
    fail_narration(e.message)
  end

  private

  attr_reader :narration

  # ── Content fetching ───────────────────────────────────────────────────

  def fetch_content
    if narration.url?
      fetch_url_content
    else
      @text = narration.source_text
    end
  end

  def fetch_url_content
    @extract_result = FetchesArticleContent.call(url: narration.source_url)

    if @extract_result.failure?
      raise ProcessingError, @extract_result.error
    end

    @text = @extract_result.data.text
  end

  # ── Character limit ────────────────────────────────────────────────────

  def check_character_limit
    character_count = @text.length
    limit = AppConfig::Mpp::CHARACTER_LIMIT

    return if character_count <= limit

    log_warn "narration_character_limit_exceeded",
      narration_id: narration.id,
      characters: character_count,
      limit: limit

    raise ProcessingError,
      "Content exceeds the #{limit.to_fs(:delimited)} character limit " \
      "(#{character_count.to_fs(:delimited)} characters)"
  end

  # ── LLM processing ────────────────────────────────────────────────────

  def process_with_llm
    log_info "narration_llm_processing_started", characters: @text.length

    @llm_result = ProcessesWithLlm.call(text: @text, episode: narration)

    if @llm_result.failure?
      log_warn "narration_llm_processing_failed", error: @llm_result.error
      raise ProcessingError, @llm_result.error
    end

    log_info "narration_llm_processing_completed", title: @llm_result.data.title
  end

  # ── Audio synthesis & upload ───────────────────────────────────────────

  def synthesize_and_upload
    content = @llm_result.data.content
    wrapped = wrap_content(content)

    narration.update!(status: :processing, processing_started_at: Time.current)

    log_info "narration_synthesizing_audio", voice: narration.voice, text_bytes: wrapped.bytesize
    audio_content = synthesize_audio(wrapped)

    gcs_episode_id = generate_episode_id
    log_info "narration_uploading_audio", gcs_episode_id: gcs_episode_id, audio_bytes: audio_content.bytesize
    upload_audio(audio_content, gcs_episode_id)

    duration_seconds = calculate_duration(audio_content)

    narration.update!(
      status: :complete,
      title: extract_title,
      author: extract_author,
      description: @llm_result.data.description,
      gcs_episode_id: gcs_episode_id,
      audio_size_bytes: audio_content.bytesize,
      duration_seconds: duration_seconds,
      processing_completed_at: Time.current
    )

    log_info "narration_completed", gcs_episode_id: gcs_episode_id
  rescue StandardError => e
    log_error "narration_audio_failed", error: e.class, message: e.message, exception: e
    cleanup_orphaned_audio
    raise
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  def extract_title
    if narration.url? && @extract_result&.data&.title.present?
      @extract_result.data.title
    else
      @llm_result.data.title
    end
  end

  def extract_author
    if narration.url? && @extract_result&.data&.author.present?
      @extract_result.data.author
    else
      @llm_result.data.author
    end
  end

  def wrap_content(content)
    BuildsEpisodeWrapper.call(
      title: extract_title,
      author: extract_author,
      include_attribution: true,
      content: content
    )
  end

  def synthesize_audio(text)
    config = Tts::Config.new(voice_name: narration.voice)
    synthesizer = SynthesizesAudio.new(config: config)
    synthesizer.call(text: text, voice: narration.voice)
  end

  def generate_episode_id
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    slug = (narration.title || "untitled").downcase
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
    Tempfile.create([ "narration", ".mp3" ]) do |temp_file|
      temp_file.binmode
      temp_file.write(audio_content)
      temp_file.close
      Mp3Info.open(temp_file.path) { |mp3| mp3.length.round }
    end
  rescue StandardError => e
    log_warn "narration_duration_calculation_failed", error: e.message
    nil
  end

  def cloud_storage
    @cloud_storage ||= CloudStorage.new(podcast_id: GCS_NARRATION_SCOPE)
  end

  def cleanup_orphaned_audio
    return unless @uploaded_audio_path

    log_info "narration_cleaning_up_orphaned_audio", path: @uploaded_audio_path
    cloud_storage.delete_file(remote_path: @uploaded_audio_path)
  rescue StandardError => e
    log_warn "narration_cleanup_failed", error: e.message
  end

  def fail_narration(error_message)
    narration.update!(status: :failed, error_message: error_message)
    log_warn "narration_marked_failed", narration_id: narration.id, error: error_message
  end
end
