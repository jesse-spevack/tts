# frozen_string_literal: true

class FetchesJinaContent
  include StructuredLogging

  FAILURE_MESSAGE = "Could not fetch content from reader service"

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    response = connection.get(jina_url)

    unless response.success?
      log_warn "jina_fetch_http_error", url: url, status: response.status
      return Result.failure(FAILURE_MESSAGE)
    end

    if response.body.bytesize > AppConfig::Content::MAX_FETCH_BYTES
      log_warn "jina_fetch_too_large", url: url, bytes: response.body.bytesize
      return Result.failure(FAILURE_MESSAGE)
    end

    parsed = JSON.parse(response.body)
    content = parsed.dig("data", "content")

    if content.blank?
      log_warn "jina_fetch_empty_content", url: url
      return Result.failure(FAILURE_MESSAGE)
    end

    log_info "jina_fetch_success", url: url, bytes: content.bytesize
    Result.success(content)
  rescue JSON::ParserError
    log_warn "jina_fetch_json_parse_error", url: url
    Result.failure(FAILURE_MESSAGE)
  rescue Faraday::TimeoutError
    log_warn "jina_fetch_timeout", url: url
    Result.failure(FAILURE_MESSAGE)
  rescue Faraday::ConnectionFailed => e
    log_warn "jina_fetch_connection_failed", url: url, error: e.message
    Result.failure(FAILURE_MESSAGE)
  end

  private

  attr_reader :url

  def jina_url
    "#{AppConfig::Content::JINA_READER_BASE_URL}/#{url}"
  end

  def connection
    Faraday.new do |f|
      f.options.timeout = 10
      f.options.open_timeout = 10
      f.headers["Accept"] = "application/json"
      f.adapter Faraday.default_adapter
    end
  end
end
