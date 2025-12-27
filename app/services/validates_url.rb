# frozen_string_literal: true

class ValidatesUrl
  def self.valid?(url)
    new(url).valid?
  end

  def initialize(url)
    @url = url
  end

  def valid?
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  private

  attr_reader :url
end
