# frozen_string_literal: true

class ExtractsArticle
  include StructuredLogging

  REMOVE_TAGS = %w[script style nav footer header aside form noscript iframe].freeze
  CONTENT_SELECTORS = %w[article main body].freeze

  ArticleData = Struct.new(:text, :title, :author, keyword_init: true) do
    def character_count
      text&.length || 0
    end
  end

  def self.call(html:)
    new(html: html).call
  end

  def initialize(html:)
    @html = html
  end

  def call
    html_size = html.bytesize
    log_info "article_extraction_request", html_bytes: html_size

    if html_size > AppConfig::Content::MAX_FETCH_BYTES
      log_warn "article_extraction_too_large", html_bytes: html_size, max_bytes: AppConfig::Content::MAX_FETCH_BYTES
      return Result.failure("Article content too large")
    end

    doc = Nokogiri::HTML(html)
    remove_unwanted_elements(doc)
    text = extract_content(doc)

    if text.length < AppConfig::Content::MIN_LENGTH
      log_warn "article_extraction_insufficient_content", extracted_chars: text.length, min_required: AppConfig::Content::MIN_LENGTH
      return Result.failure("Could not extract article content")
    end

    log_info "article_extraction_success", extracted_chars: text.length
    Result.success(ArticleData.new(text: text, title: extract_title(doc), author: extract_author(doc)))
  end

  private

  attr_reader :html

  def remove_unwanted_elements(doc)
    REMOVE_TAGS.each do |tag|
      doc.css(tag).remove
    end
  end

  def extract_content(doc)
    content_node = find_content_node(doc)
    return "" unless content_node

    content_node.text.gsub(/\s+/, " ").strip
  end

  def find_content_node(doc)
    CONTENT_SELECTORS.each do |selector|
      node = doc.at_css(selector)
      return node if node && node.text.strip.length >= AppConfig::Content::MIN_LENGTH
    end
    nil
  end

  def extract_title(doc)
    doc.at_css("title")&.text&.strip.presence
  end

  def extract_author(doc)
    extract_author_from_meta(doc, 'meta[name="author"]') ||
      extract_author_from_meta(doc, 'meta[property="article:author"]') ||
      extract_author_from_meta(doc, 'meta[property="og:article:author"]') ||
      extract_author_from_meta(doc, 'meta[name="twitter:creator"]') ||
      extract_author_from_element(doc, '[rel="author"]') ||
      extract_author_from_element(doc, ".byline") ||
      extract_author_from_element(doc, ".author")
  end

  def extract_author_from_meta(doc, selector)
    doc.at_css(selector)&.[]("content")&.strip.presence
  end

  def extract_author_from_element(doc, selector)
    doc.at_css(selector)&.text&.strip.presence
  end
end
