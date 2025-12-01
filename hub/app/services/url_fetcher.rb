class UrlFetcher
  TIMEOUT_SECONDS = 10
  DNS_TIMEOUT_SECONDS = 5
  MAX_CONTENT_LENGTH = 10 * 1024 * 1024 # 10MB

  # SSRF protection: block private/internal IP ranges
  BLOCKED_IP_RANGES = [
    IPAddr.new("127.0.0.0/8"),       # Loopback
    IPAddr.new("10.0.0.0/8"),        # Private class A
    IPAddr.new("172.16.0.0/12"),     # Private class B
    IPAddr.new("192.168.0.0/16"),    # Private class C
    IPAddr.new("169.254.0.0/16"),    # Link-local / cloud metadata
    IPAddr.new("0.0.0.0/8"),         # Current network
    IPAddr.new("::1/128"),           # IPv6 loopback
    IPAddr.new("fc00::/7"),          # IPv6 private
    IPAddr.new("fe80::/10")          # IPv6 link-local
  ].freeze

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

    unless safe_host?
      Rails.logger.warn "event=url_blocked_internal url=#{url}"
      return Result.failure("URL not allowed")
    end

    # Check Content-Length via HEAD request first (if available)
    head_response = connection.head(url)
    content_length = head_response.headers["content-length"]&.to_i

    if content_length && content_length > MAX_CONTENT_LENGTH
      Rails.logger.warn "event=url_fetch_too_large url=#{url} content_length=#{content_length} max=#{MAX_CONTENT_LENGTH}"
      return Result.failure("Content too large")
    end

    Rails.logger.info "event=url_fetch_request url=#{url}"
    response = connection.get(url)

    unless response.success?
      Rails.logger.warn "event=url_fetch_http_error url=#{url} status=#{response.status}"
      return Result.failure("Could not fetch URL")
    end

    # Double-check actual body size
    if response.body.bytesize > MAX_CONTENT_LENGTH
      Rails.logger.warn "event=url_fetch_body_too_large url=#{url} bytes=#{response.body.bytesize}"
      return Result.failure("Content too large")
    end

    Rails.logger.info "event=url_fetch_success url=#{url} status=#{response.status} bytes=#{response.body.bytesize}"
    Result.success(response.body)
  rescue Faraday::TimeoutError
    Rails.logger.warn "event=url_fetch_timeout url=#{url}"
    Result.failure("Could not fetch URL")
  rescue Faraday::ConnectionFailed => e
    Rails.logger.warn "event=url_fetch_connection_failed url=#{url} error=#{e.message}"
    Result.failure("Could not fetch URL")
  end

  private

  attr_reader :url

  def valid_url?
    UrlValidator.valid?(url)
  end

  def safe_host?
    uri = URI.parse(url)
    return false if uri.host.nil?

    # Resolve DNS to check actual IP (with timeout)
    addresses = Timeout.timeout(DNS_TIMEOUT_SECONDS) do
      Resolv.getaddresses(uri.host)
    end
    return false if addresses.empty?

    addresses.none? { |addr| blocked_ip?(addr) }
  rescue Resolv::ResolvError, Timeout::Error
    false
  end

  def blocked_ip?(ip_string)
    ip = IPAddr.new(ip_string)
    BLOCKED_IP_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true # Block if we can't parse the IP
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
