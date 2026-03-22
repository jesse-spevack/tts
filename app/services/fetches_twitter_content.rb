# frozen_string_literal: true

class FetchesTwitterContent
  include StructuredLogging

  FXTWITTER_BASE_URL = "https://api.fxtwitter.com"
  FAILURE_MESSAGE = "Could not fetch Twitter content"

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    username = NormalizesTwitterUrl.extract_username(url)
    tweet_id = NormalizesTwitterUrl.extract_tweet_id(url)

    unless username && tweet_id
      log_warn "twitter_fetch_invalid_url", url: url
      return Result.failure(FAILURE_MESSAGE)
    end

    fxtwitter_result = fetch_from_fxtwitter(username, tweet_id)
    return fxtwitter_result if fxtwitter_result.success?

    log_info "twitter_fxtwitter_failed_trying_jina", url: url
    fetch_from_jina
  end

  private

  attr_reader :url

  def fetch_from_fxtwitter(username, tweet_id)
    response = connection.get("#{FXTWITTER_BASE_URL}/#{username}/status/#{tweet_id}")

    unless response.success?
      log_warn "twitter_fxtwitter_http_error", url: url, status: response.status
      return Result.failure(FAILURE_MESSAGE)
    end

    parsed = JSON.parse(response.body)
    tweet = parsed["tweet"]

    unless tweet
      log_warn "twitter_fxtwitter_no_tweet", url: url
      return Result.failure(FAILURE_MESSAGE)
    end

    author_name = tweet.dig("author", "name")
    author_screen_name = tweet.dig("author", "screen_name")
    author = format_author(author_name, author_screen_name)

    article_blocks = tweet.dig("article", "content", "blocks")
    article_data = ConvertsTwitterArticleBlocks.call(blocks: article_blocks) || extract_text_content(tweet)

    unless article_data
      log_warn "twitter_fxtwitter_no_content", url: url
      return Result.failure(FAILURE_MESSAGE)
    end

    log_info "twitter_fxtwitter_success", url: url, chars: article_data.character_count
    Result.success(
      ExtractsArticle::ArticleData.new(
        text: article_data.text,
        title: article_data.title,
        author: author
      )
    )
  rescue JSON::ParserError
    log_warn "twitter_fxtwitter_json_parse_error", url: url
    Result.failure(FAILURE_MESSAGE)
  rescue Faraday::TimeoutError => e
    log_warn "twitter_fxtwitter_timeout", url: url
    Result.failure(FAILURE_MESSAGE)
  rescue Faraday::ConnectionFailed => e
    log_warn "twitter_fxtwitter_connection_failed", url: url, error: e.message
    Result.failure(FAILURE_MESSAGE)
  end

  def extract_text_content(tweet)
    text = tweet["text"]
    return nil if text.blank?

    ExtractsArticle::ArticleData.new(text: text, title: nil, author: nil)
  end

  def format_author(name, screen_name)
    if name.present? && screen_name.present?
      "#{name} (@#{screen_name})"
    elsif name.present?
      name
    elsif screen_name.present?
      "@#{screen_name}"
    end
  end

  def fetch_from_jina
    jina_result = FetchesJinaContent.call(url: url)

    if jina_result.success?
      log_info "twitter_jina_fallback_success", url: url, chars: jina_result.data.length
      Result.success(
        ExtractsArticle::ArticleData.new(text: jina_result.data, title: nil, author: nil)
      )
    else
      log_warn "twitter_jina_fallback_failed", url: url
      Result.failure(FAILURE_MESSAGE)
    end
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
