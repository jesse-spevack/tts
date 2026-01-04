# frozen_string_literal: true

class FetchesUrl
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

    if content_length && content_length > AppConfig::Content::MAX_FETCH_BYTES
      Rails.logger.warn "event=url_fetch_too_large url=#{url} content_length=#{content_length} max=#{AppConfig::Content::MAX_FETCH_BYTES}"
      return Result.failure("Content too large")
    end

    Rails.logger.info "event=url_fetch_request url=#{url}"
    response = connection.get(url)

    unless response.success?
      Rails.logger.warn "event=url_fetch_http_error url=#{url} status=#{response.status}"
      return Result.failure("Could not fetch URL")
    end

    # Double-check actual body size
    if response.body.bytesize > AppConfig::Content::MAX_FETCH_BYTES
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
    ValidatesUrl.call(url)
  end

  def safe_host?
    uri = URI.parse(url)
    return false if uri.host.nil?

    # Resolve DNS to check actual IP (with timeout)
    addresses = Timeout.timeout(AppConfig::Network::DNS_TIMEOUT_SECONDS) do
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
      f.options.timeout = AppConfig::Network::TIMEOUT_SECONDS
      f.options.open_timeout = AppConfig::Network::TIMEOUT_SECONDS
      f.response :follow_redirects, callback: method(:validate_redirect_target)
      f.adapter Faraday.default_adapter
    end
  end

  # Callback to validate each redirect target against SSRF blocklist
  # This prevents DNS rebinding attacks where initial DNS is safe but redirect resolves to internal IP
  def validate_redirect_target(_old_env, new_env)
    new_url = new_env[:url].to_s
    new_uri = URI.parse(new_url)

    return if new_uri.host.nil?

    addresses = Timeout.timeout(AppConfig::Network::DNS_TIMEOUT_SECONDS) do
      Resolv.getaddresses(new_uri.host)
    end

    if addresses.empty? || addresses.any? { |addr| blocked_ip?(addr) }
      Rails.logger.warn "event=redirect_blocked_internal url=#{new_url}"
      raise Faraday::ConnectionFailed, "Redirect to blocked address"
    end
  rescue Resolv::ResolvError, Timeout::Error
    Rails.logger.warn "event=redirect_dns_failed url=#{new_url}"
    raise Faraday::ConnectionFailed, "Redirect DNS resolution failed"
  end
end
