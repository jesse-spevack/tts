# frozen_string_literal: true

class ProcessPasteEpisode
  include EpisodeLogging

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
    @user = episode.user
  end

  def call
    log_info "process_paste_episode_started", text_length: episode.source_text.length

    check_character_limit
    process_with_llm
    update_and_enqueue

    log_info "process_paste_episode_completed"
  rescue ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_paste_episode_error", error: e.class, message: e.message
    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def check_character_limit
    max_chars = MaxCharactersForUser.call(user: user)
    return unless max_chars && episode.source_text.length > max_chars

    log_warn "character_limit_exceeded", characters: episode.source_text.length, limit: max_chars, tier: user.tier
    raise ProcessingError, "This content is too long for your account tier"
  end

  def process_with_llm
    log_info "llm_processing_started", characters: episode.source_text.length

    @llm_result = ProcessesWithLlm.call(text: episode.source_text, episode: episode)
    if @llm_result.failure?
      log_warn "llm_processing_failed", error: @llm_result.error
      raise ProcessingError, @llm_result.error
    end

    log_info "llm_processing_completed", title: @llm_result.title
  end

  def update_and_enqueue
    content = @llm_result.content

    Episode.transaction do
      episode.update!(
        title: @llm_result.title,
        author: @llm_result.author,
        description: @llm_result.description,
        content_preview: GeneratesContentPreview.call(content)
      )

      log_info "episode_metadata_updated"

      SubmitEpisodeForProcessing.call(episode: episode, content: content)
    end
  end

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    log_warn "episode_marked_failed", error: error_message
  end

  class ProcessingError < StandardError; end
end
