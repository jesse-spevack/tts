# frozen_string_literal: true

class ValidatesUrl
  def self.call(url)
    new(url).call
  end

  def initialize(url)
    @url = url
  end

  def call
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  private

  attr_reader :url
end
