# frozen_string_literal: true

class NormalizesSubstackUrl
  SUBSTACK_TRACKING_PARAMS = %w[
    r
    utm_campaign
    utm_medium
    utm_source
    showWelcomeOnShare
    triedRedirect
  ].freeze

  def self.call(url:)
    new(url: url).call
  end

  def initialize(url:)
    @url = url
  end

  def call
    uri = URI.parse(url)

    return Result.failure(inbox_error_message) if inbox_url?(uri)

    uri = normalize_open_substack(uri) if uri.host == "open.substack.com"
    uri = strip_substack_tracking_params(uri) if substack_domain?(uri)

    Result.success(uri.to_s)
  rescue URI::InvalidURIError
    Result.success(url)
  end

  private

  attr_reader :url

  def inbox_url?(uri)
    uri.host&.match?(/\A(www\.)?substack\.com\z/) && uri.path&.start_with?("/inbox")
  end

  def inbox_error_message
    "Substack inbox links require login. Please use the article's direct URL " \
    "(e.g., author.substack.com/p/title)."
  end

  def normalize_open_substack(uri)
    parts = uri.path.split("/")
    return uri unless parts.length >= 4 && parts[1] == "pub"

    author = parts[2]
    rest = parts[3..].join("/")
    URI.parse("https://#{author}.substack.com/#{rest}")
  end

  def strip_substack_tracking_params(uri)
    return uri unless uri.query

    params = URI.decode_www_form(uri.query).reject { |key, _| SUBSTACK_TRACKING_PARAMS.include?(key) }
    uri.query = params.empty? ? nil : URI.encode_www_form(params)
    uri
  end

  def substack_domain?(uri)
    uri.host&.end_with?(".substack.com")
  end
end
