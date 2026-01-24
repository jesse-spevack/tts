# frozen_string_literal: true

class ProcessesEmailEpisode
  include EpisodeErrorHandling

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
    @user = episode.user
  end

  def call
    log_info "process_email_episode_started", text_length: episode.source_text.length

    check_character_limit
    process_with_llm
    update_and_enqueue

    log_info "process_email_episode_completed"
  rescue EpisodeErrorHandling::ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_email_episode_error", error: e.class, message: e.message
    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def check_character_limit
    result = ValidatesCharacterLimit.call(
      user: user,
      character_count: episode.source_text.length
    )

    return if result.success?

    log_warn "character_limit_exceeded",
      characters: episode.source_text.length,
      limit: user.character_limit

    raise EpisodeErrorHandling::ProcessingError, result.error
  end

  def process_with_llm
    log_info "llm_processing_started", characters: episode.source_text.length

    @llm_result = ProcessesWithLlm.call(text: episode.source_text, episode: episode)
    if @llm_result.failure?
      log_warn "llm_processing_failed", error: @llm_result.error
      raise EpisodeErrorHandling::ProcessingError, @llm_result.error
    end

    log_info "llm_processing_completed", title: @llm_result.data.title
  end

  def update_and_enqueue
    content = @llm_result.data.content

    episode.update!(
      title: @llm_result.data.title,
      author: @llm_result.data.author,
      description: @llm_result.data.description,
      content_preview: GeneratesContentPreview.call(content)
    )

    log_info "episode_metadata_updated"

    SubmitsEpisodeForProcessing.call(episode: episode, content: content)
  end
end
