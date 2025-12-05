# frozen_string_literal: true

class UrlNormalizer
  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    uri = URI.parse(url)
    uri = normalize_open_substack(uri) if uri.host == "open.substack.com"
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  private

  attr_reader :url

  def normalize_open_substack(uri)
    parts = uri.path.split("/")
    return uri unless parts.length >= 4 && parts[1] == "pub"

    author = parts[2]
    rest = parts[3..].join("/")
    URI.parse("https://#{author}.substack.com/#{rest}")
  end
end
