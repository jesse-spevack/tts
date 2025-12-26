# frozen_string_literal: true

class SubmitEpisodeForProcessing
  # Podcasts that use internal TTS processing (Hub) instead of external generator (Cloud Run)
  INTERNAL_TTS_PODCAST_IDS = [
    "podcast_195c82bf8eeb2aae"  # Jesse's podcast for testing
  ].freeze

  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    if use_internal_tts?
      process_internally
    else
      process_externally
    end
  end

  private

  attr_reader :episode, :content

  def use_internal_tts?
    INTERNAL_TTS_PODCAST_IDS.include?(episode.podcast.podcast_id)
  end

  def process_internally
    Rails.logger.info "event=internal_tts_selected episode_id=#{episode.id} podcast_id=#{episode.podcast.podcast_id}"

    wrapped = wrap_content
    episode.update!(source_text: wrapped)

    GenerateAudioJob.perform_later(episode)

    Rails.logger.info "event=internal_processing_enqueued episode_id=#{episode.id}"
  end

  def process_externally
    staging_path = upload_content(wrap_content)

    Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

    enqueue_processing(staging_path)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  def wrap_content
    BuildEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      tier: episode.user.tier,
      content: content
    )
  end

  def upload_content(wrapped_content)
    UploadEpisodeContent.call(episode: episode, content: wrapped_content)
  end

  def enqueue_processing(staging_path)
    EnqueueEpisodeProcessing.call(episode: episode, staging_path: staging_path)
  end
end
