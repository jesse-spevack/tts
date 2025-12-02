# frozen_string_literal: true

module MarkdownStripper
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_images(text)
    text = convert_links(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text.strip
  end

  def self.remove_images(text)
    text.gsub(/!\[([^\]]*)\]\([^)]+\)/, "")
  end

  def self.convert_links(text)
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def self.remove_headers(text)
    text.gsub(/^\#{1,6}\s+/, "")
  end

  def self.remove_formatting(text)
    text = text.gsub(/(\*\*|__)(.*?)\1/, '\2')
    text.gsub(/(\*|_)(.*?)\1/, '\2')
  end

  def self.remove_strikethrough(text)
    text.gsub(/~~(.*?)~~/, '\1')
  end
end
