# frozen_string_literal: true

class ProcessUrlEpisode
  include EpisodeLogging

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
  rescue ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_url_episode_error", error: e.class, message: e.message

    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_url
    log_info "url_normalization_started", url: episode.source_url
    normalized_url = NormalizesUrl.call(url: episode.source_url)
    log_info "url_fetch_started", url: normalized_url

    @fetch_result = FetchesUrl.call(url: normalized_url)
    if @fetch_result.failure?
      log_warn "url_fetch_failed", error: @fetch_result.error

      raise ProcessingError, @fetch_result.error
    end

    log_info "url_fetch_completed", bytes: @fetch_result.html.bytesize
  end

  def extract_content
    log_info "article_extraction_started"

    @extract_result = ExtractsArticle.call(html: @fetch_result.html)
    if @extract_result.failure?
      log_warn "article_extraction_failed", error: @extract_result.error

      raise ProcessingError, @extract_result.error
    end

    log_info "article_extraction_completed", characters: @extract_result.character_count
  end

  def check_character_limit
    max_chars = MaxCharactersForUser.call(user: user)
    return unless max_chars && @extract_result.character_count > max_chars

    log_warn "character_limit_exceeded", characters: @extract_result.character_count, limit: max_chars, tier: user.tier

    raise ProcessingError, "This content is too long for your account tier"
  end

  def process_with_llm
    log_info "llm_processing_started", characters: @extract_result.character_count

    @llm_result = LlmProcessor.call(text: @extract_result.text, episode: episode)
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
        title: @extract_result.title || @llm_result.title,
        author: @extract_result.author || @llm_result.author,
        description: @llm_result.description,
        content_preview: ContentPreview.generate(content)
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
