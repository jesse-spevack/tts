# frozen_string_literal: true

class FormatsEpisodeDescription
  def self.call(description:, source_url: nil)
    new(description: description, source_url: source_url).call
  end

  def initialize(description:, source_url: nil)
    @description = description
    @source_url = source_url
  end

  def call
    return description if source_url.blank?

    "#{description}\n\nOriginal URL: #{source_url}"
  end

  private

  attr_reader :description, :source_url
end
