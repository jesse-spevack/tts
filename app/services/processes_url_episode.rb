# frozen_string_literal: true

class ProcessesUrlEpisode
  include EpisodeErrorHandling

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
    @user = episode.user
  end

  def call
    log_info "process_url_episode_started", url: episode.source_url

    episode.update!(status: :preparing)
    fetch_and_extract
    check_character_limit
    process_with_llm
    update_and_enqueue

    log_info "process_url_episode_completed"
  rescue EpisodeErrorHandling::ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_url_episode_error", error: e.class, message: e.message, exception: e

    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_and_extract
    @extract_result = FetchesArticleContent.call(url: episode.source_url)

    if @extract_result.failure?
      raise EpisodeErrorHandling::ProcessingError, @extract_result.error
    end
  end

  def check_character_limit
    result = ValidatesCharacterLimit.call(
      user: user,
      character_count: @extract_result.data.character_count
    )

    return if result.success?

    log_warn "character_limit_exceeded",
      characters: @extract_result.data.character_count,
      limit: user.character_limit

    raise EpisodeErrorHandling::ProcessingError, result.error
  end

  def process_with_llm
    log_info "llm_processing_started", characters: @extract_result.data.character_count

    @llm_result = ProcessesWithLlm.call(text: @extract_result.data.text, episode: episode)
    if @llm_result.failure?
      log_warn "llm_processing_failed", error: @llm_result.error

      raise EpisodeErrorHandling::ProcessingError, @llm_result.error
    end

    log_info "llm_processing_completed", title: @llm_result.data.title
  end

  def update_and_enqueue
    content = @llm_result.data.content
    description = FormatsEpisodeDescription.call(
      description: @llm_result.data.description,
      source_url: episode.source_url
    )

    episode.update!(
      title: @extract_result.data.title || @llm_result.data.title,
      author: @extract_result.data.author || @llm_result.data.author,
      description: description,
      content_preview: GeneratesContentPreview.call(content),
      status: :preparing
    )

    log_info "episode_metadata_updated"

    SubmitsEpisodeForProcessing.call(episode: episode, content: content)
  end
end
