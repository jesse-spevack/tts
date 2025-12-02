# frozen_string_literal: true

# Strips markdown syntax from text, leaving only plain text content.
#
# NOTE: This logic is duplicated from lib/text_converter.rb. The duplication
# exists because Hub (Rails app) and the TTS lib have separate load paths and
# don't share code. We chose duplication over adding cross-project dependencies
# for this simple, stable functionality.
#
# See also: lib/text_converter.rb
module MarkdownStripper
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_yaml_frontmatter(text)
    text = remove_code_blocks(text)
    text = remove_images(text)
    text = convert_links(text)
    text = remove_html_tags(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text = remove_inline_code(text)
    text = remove_unordered_lists(text)
    text = remove_ordered_lists(text)
    text = remove_blockquotes(text)
    text = remove_horizontal_rules(text)
    text.strip
  end

  def self.remove_code_blocks(text)
    text.gsub(/```[\s\S]*?```/m, "")
  end

  def self.remove_inline_code(text)
    text.gsub(/`([^`]+)`/, '\1')
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

  def self.remove_unordered_lists(text)
    text.gsub(/^\s*[-*+]\s+/, "")
  end

  def self.remove_ordered_lists(text)
    text.gsub(/^\s*\d+\.\s+/, "")
  end

  def self.remove_blockquotes(text)
    text.gsub(/^\s*>\s?/, "")
  end

  def self.remove_horizontal_rules(text)
    text.gsub(/^(\*{3,}|-{3,}|_{3,})$/, "")
  end

  def self.remove_yaml_frontmatter(text)
    text.gsub(/\A---\s*\n.*?\n---\s*\n/m, "")
  end

  def self.remove_html_tags(text)
    text.gsub(/<[^>]+>/, "")
  end
end
