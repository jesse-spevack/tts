# frozen_string_literal: true

class StripsUrlTrackingParams
  def self.call(url)
    new(url).call
  end

  def initialize(url)
    @url = url
  end

  def call
    uri = URI.parse(url)
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  private

  attr_reader :url
end
