# Converts markdown text to plain text by stripping all markdown syntax.
# Used by TextProcessor to prepare content for TTS conversion.
#
# NOTE: This logic is duplicated in hub/app/services/markdown_stripper.rb.
# The duplication exists because Hub (Rails app) and the TTS lib have separate
# load paths and don't share code. We chose duplication over adding cross-project
# dependencies for this simple, stable functionality.
#
# See also: hub/app/services/markdown_stripper.rb
module TextConverter
  def self.remove_yaml_frontmatter(text)
    text.gsub(/\A---\s*\n.*?\n---\s*\n/m, "")
  end

  def self.remove_code_blocks(text)
    text = text.gsub(/```[\s\S]*?```/m, "")
    text.gsub(/^\s{4,}.*$/, "")
  end

  def self.remove_images(text)
    text.gsub(/!\[([^\]]*)\]\([^)]+\)/, "")
  end

  def self.convert_links(text)
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def self.remove_html_tags(text)
    text.gsub(/<[^>]+>/, "")
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

  def self.remove_horizontal_rules(text)
    text.gsub(/^(\*{3,}|-{3,}|_{3,})$/, "")
  end

  def self.remove_blockquotes(text)
    text.gsub(/^\s*>\s?/, "")
  end

  def self.remove_inline_code(text)
    text.gsub(/`([^`]+)`/, '\1')
  end

  def self.clean_whitespace(text)
    text.gsub(/\n{3,}/, "\n\n").strip
  end
end
