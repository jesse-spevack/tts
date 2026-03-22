# frozen_string_literal: true

class NormalizesTwitterUrl
  TWITTER_HOSTS = %w[
    twitter.com
    www.twitter.com
    mobile.twitter.com
    x.com
    www.x.com
  ].freeze

  # Matches /{username}/status/{tweet_id} with optional trailing path segments
  STATUS_PATH_PATTERN = %r{\A/([^/]+)/status/(\d+)}

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    uri = URI.parse(url)
    return Result.success(url) unless twitter_host?(uri)

    uri.host = "x.com"
    uri.scheme = "https"

    Result.success(uri.to_s)
  rescue URI::InvalidURIError
    Result.success(url)
  end

  def self.twitter_url?(url)
    uri = URI.parse(url)
    host = uri.host&.downcase
    TWITTER_HOSTS.include?(host)
  rescue URI::InvalidURIError
    false
  end

  def self.extract_tweet_id(url)
    uri = URI.parse(url)
    match = uri.path&.match(STATUS_PATH_PATTERN)
    match ? match[2] : nil
  rescue URI::InvalidURIError
    nil
  end

  def self.extract_username(url)
    uri = URI.parse(url)
    match = uri.path&.match(STATUS_PATH_PATTERN)
    match ? match[1] : nil
  rescue URI::InvalidURIError
    nil
  end

  private

  attr_reader :url

  def twitter_host?(uri)
    host = uri.host&.downcase
    TWITTER_HOSTS.include?(host)
  end
end
