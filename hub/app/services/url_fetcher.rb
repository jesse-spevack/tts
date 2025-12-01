class UrlFetcher
  TIMEOUT_SECONDS = 10

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    unless valid_url?
      Rails.logger.warn "event=url_validation_failed url=#{url}"
      return Result.failure("Invalid URL")
    end

    Rails.logger.info "event=url_fetch_request url=#{url}"
    response = connection.get(url)

    unless response.success?
      Rails.logger.warn "event=url_fetch_http_error url=#{url} status=#{response.status}"
      return Result.failure("Could not fetch URL")
    end

    Rails.logger.info "event=url_fetch_success url=#{url} status=#{response.status} bytes=#{response.body.bytesize}"
    Result.success(response.body)
  rescue Faraday::TimeoutError => e
    Rails.logger.warn "event=url_fetch_timeout url=#{url}"
    Result.failure("Could not fetch URL")
  rescue Faraday::ConnectionFailed => e
    Rails.logger.warn "event=url_fetch_connection_failed url=#{url} error=#{e.message}"
    Result.failure("Could not fetch URL")
  end

  private

  attr_reader :url

  def valid_url?
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
      f.response :follow_redirects
      f.adapter Faraday.default_adapter
    end
  end

  class Result
    attr_reader :html, :error

    def self.success(html)
      new(html: html, error: nil)
    end

    def self.failure(error)
      new(html: nil, error: error)
    end

    def initialize(html:, error:)
      @html = html
      @error = error
    end

    def success?
      error.nil?
    end

    def failure?
      !success?
    end
  end
end
