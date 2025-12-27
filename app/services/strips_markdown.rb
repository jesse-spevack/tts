# frozen_string_literal: true

# Strips markdown syntax from text, leaving only plain text content.
# Used by GeneratesContentPreview for episode cards and by UploadAndEnqueueEpisode
# to convert markdown to plain text before sending to TTS processing.
class StripsMarkdown
  def self.call(text)
    new(text).call
  end

  def initialize(text)
    @text = text
  end

  def call
    return text if text.nil?
    return text if text.empty?

    result = text.dup
    result = remove_yaml_frontmatter(result)
    result = remove_code_blocks(result)
    result = remove_images(result)
    result = convert_links(result)
    result = remove_html_tags(result)
    result = remove_headers(result)
    result = remove_formatting(result)
    result = remove_strikethrough(result)
    result = remove_inline_code(result)
    result = remove_unordered_lists(result)
    result = remove_ordered_lists(result)
    result = remove_blockquotes(result)
    result = remove_horizontal_rules(result)
    clean_whitespace(result)
  end

  private

  attr_reader :text

  def remove_code_blocks(text)
    text.gsub(/```[\s\S]*?```/m, "")
  end

  def remove_inline_code(text)
    text.gsub(/`([^`]+)`/, '\1')
  end

  def remove_images(text)
    text.gsub(/!\[([^\]]*)\]\([^)]+\)/, "")
  end

  def convert_links(text)
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def remove_headers(text)
    text.gsub(/^\#{1,6}\s+/, "")
  end

  def remove_formatting(text)
    result = text.gsub(/(\*\*|__)(.*?)\1/, '\2')
    result.gsub(/(\*|_)(.*?)\1/, '\2')
  end

  def remove_strikethrough(text)
    text.gsub(/~~(.*?)~~/, '\1')
  end

  def remove_unordered_lists(text)
    text.gsub(/^\s*[-*+]\s+/, "")
  end

  def remove_ordered_lists(text)
    text.gsub(/^\s*\d+\.\s+/, "")
  end

  def remove_blockquotes(text)
    text.gsub(/^\s*>\s?/, "")
  end

  def remove_horizontal_rules(text)
    text.gsub(/^(\*{3,}|-{3,}|_{3,})$/, "")
  end

  def remove_yaml_frontmatter(text)
    text.gsub(/\A---\s*\n.*?\n---\s*\n/m, "")
  end

  def remove_html_tags(text)
    text.gsub(/<[^>]+>/, "")
  end

  def clean_whitespace(text)
    text.gsub(/\n{3,}/, "\n\n").strip
  end
end
