class UrlFetcher
  TIMEOUT_SECONDS = 10

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    return Result.failure("Invalid URL") unless valid_url?

    response = connection.get(url)
    return Result.failure("Could not fetch URL") unless response.success?

    Result.success(response.body)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
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
