# frozen_string_literal: true

class ProcessUrlEpisode
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

    fetch_url
    extract_content
    check_character_limit
    process_with_llm
    update_and_enqueue

    log_info "process_url_episode_completed"
  rescue EpisodeErrorHandling::ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_url_episode_error", error: e.class, message: e.message

    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_url
    log_info "url_fetch_started", url: episode.source_url

    @fetch_result = FetchesUrl.call(url: episode.source_url)
    if @fetch_result.failure?
      log_warn "url_fetch_failed", error: @fetch_result.error

      raise EpisodeErrorHandling::ProcessingError, @fetch_result.error
    end

    log_info "url_fetch_completed", bytes: @fetch_result.data.bytesize
  end

  def extract_content
    log_info "article_extraction_started"

    @extract_result = ExtractsArticle.call(html: @fetch_result.data)
    if @extract_result.failure?
      log_warn "article_extraction_failed", error: @extract_result.error

      raise EpisodeErrorHandling::ProcessingError, @extract_result.error
    end

    log_info "article_extraction_completed", characters: @extract_result.data.character_count
  end

  def check_character_limit
    max_chars = user.character_limit
    return unless max_chars && @extract_result.data.character_count > max_chars

    log_warn "character_limit_exceeded", characters: @extract_result.data.character_count, limit: max_chars

    raise EpisodeErrorHandling::ProcessingError,
      "Content exceeds your plan's #{max_chars.to_fs(:delimited)} character limit " \
      "(#{@extract_result.data.character_count.to_fs(:delimited)} characters)"
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

    Episode.transaction do
      episode.update!(
        title: @extract_result.data.title || @llm_result.data.title,
        author: @extract_result.data.author || @llm_result.data.author,
        description: @llm_result.data.description,
        content_preview: GeneratesContentPreview.call(content)
      )

      log_info "episode_metadata_updated"

      SubmitEpisodeForProcessing.call(episode: episode, content: content)
    end
  end
end
