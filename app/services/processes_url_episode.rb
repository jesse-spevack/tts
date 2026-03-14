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
    log_error "process_url_episode_error", error: e.class, message: e.message

    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_and_extract
    log_info "url_fetch_started", url: episode.source_url

    fetch_result = FetchesUrl.call(url: episode.source_url)

    if fetch_result.success?
      log_info "url_fetch_completed", bytes: fetch_result.data.bytesize
      @extract_result = extract_content(fetch_result.data)
      attempt_jina_extraction_fallback(fetch_result) if low_quality_extraction?(@extract_result, fetch_result)
    else
      log_warn "url_fetch_failed", error: fetch_result.error
      @extract_result = fetch_via_jina
    end
  end

  def fetch_via_jina
    log_info "jina_fetch_fallback_started", url: episode.source_url

    jina_result = FetchesJinaContent.call(url: episode.source_url)

    if jina_result.failure?
      log_warn "jina_fetch_fallback_failed", url: episode.source_url
      raise EpisodeErrorHandling::ProcessingError, "Could not fetch URL"
    end

    log_info "jina_fetch_fallback_success", url: episode.source_url, chars: jina_result.data.length
    Result.success(
      ExtractsArticle::ArticleData.new(text: jina_result.data, title: nil, author: nil)
    )
  end

  def extract_content(html)
    log_info "article_extraction_started"

    result = ExtractsArticle.call(html: html)
    if result.failure?
      log_warn "article_extraction_failed", error: result.error
      raise EpisodeErrorHandling::ProcessingError, result.error
    end

    log_info "article_extraction_completed", characters: result.data.character_count
    result
  end

  def low_quality_extraction?(extract_result, fetch_result)
    extract_result.data.character_count < AppConfig::Content::LOW_QUALITY_EXTRACTION_CHARS &&
      fetch_result.data.bytesize > AppConfig::Content::LOW_QUALITY_HTML_MIN_BYTES
  end

  def attempt_jina_extraction_fallback(fetch_result)
    log_info "low_quality_extraction_detected",
      extracted_chars: @extract_result.data.character_count,
      html_bytes: fetch_result.data.bytesize

    jina_result = FetchesJinaContent.call(url: episode.source_url)

    if jina_result.success?
      log_info "jina_fallback_success", chars: jina_result.data.length
      @extract_result = Result.success(
        ExtractsArticle::ArticleData.new(
          text: jina_result.data,
          title: @extract_result.data.title,
          author: @extract_result.data.author
        )
      )
    else
      log_warn "jina_fallback_failed", error: jina_result.error
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
