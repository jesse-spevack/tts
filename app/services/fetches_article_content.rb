# frozen_string_literal: true

class FetchesArticleContent
  include StructuredLogging

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    log_info "url_fetch_started", url: url

    fetch_result = FetchesUrl.call(url: url)

    if fetch_result.success?
      log_info "url_fetch_completed", bytes: fetch_result.data.bytesize
      extract_result = extract_content(fetch_result.data)
      return extract_result if extract_result.failure?

      extract_result = attempt_jina_extraction_fallback(extract_result, fetch_result) if low_quality_extraction?(extract_result, fetch_result)
      extract_result
    else
      log_warn "url_fetch_failed", error: fetch_result.error
      fetch_via_jina
    end
  end

  private

  attr_reader :url

  def extract_content(html)
    log_info "article_extraction_started"

    result = ExtractsArticle.call(html: html)
    if result.failure?
      log_warn "article_extraction_failed", error: result.error
      return result
    end

    log_info "article_extraction_completed", characters: result.data.character_count
    result
  end

  def low_quality_extraction?(extract_result, fetch_result)
    extract_result.data.character_count < AppConfig::Content::LOW_QUALITY_EXTRACTION_CHARS &&
      fetch_result.data.bytesize > AppConfig::Content::LOW_QUALITY_HTML_MIN_BYTES
  end

  def attempt_jina_extraction_fallback(extract_result, fetch_result)
    log_info "low_quality_extraction_detected",
      extracted_chars: extract_result.data.character_count,
      html_bytes: fetch_result.data.bytesize

    jina_result = FetchesJinaContent.call(url: url)

    if jina_result.success?
      log_info "jina_fallback_success", chars: jina_result.data.length
      Result.success(
        ExtractsArticle::ArticleData.new(
          text: jina_result.data,
          title: extract_result.data.title,
          author: extract_result.data.author
        )
      )
    else
      log_warn "jina_fallback_failed", error: jina_result.error
      extract_result
    end
  end

  def fetch_via_jina
    log_info "jina_fetch_fallback_started", url: url

    jina_result = FetchesJinaContent.call(url: url)

    if jina_result.failure?
      log_warn "jina_fetch_fallback_failed", url: url
      return Result.failure("Could not fetch URL")
    end

    log_info "jina_fetch_fallback_success", url: url, chars: jina_result.data.length
    Result.success(
      ExtractsArticle::ArticleData.new(text: jina_result.data, title: nil, author: nil)
    )
  end
end
