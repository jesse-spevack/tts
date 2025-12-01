class ArticleExtractor
  REMOVE_TAGS = %w[script style nav footer header aside form noscript iframe].freeze
  CONTENT_SELECTORS = %w[article main body].freeze
  MIN_CONTENT_LENGTH = 100
  MAX_HTML_BYTES = 10 * 1024 * 1024 # 10MB

  def self.call(html:)
    new(html: html).call
  end

  def initialize(html:)
    @html = html
  end

  def call
    html_size = html.bytesize
    Rails.logger.info "event=article_extraction_request html_bytes=#{html_size}"

    if html_size > MAX_HTML_BYTES
      Rails.logger.warn "event=article_extraction_too_large html_bytes=#{html_size} max_bytes=#{MAX_HTML_BYTES}"
      return Result.failure("Article content too large")
    end

    doc = Nokogiri::HTML(html)
    remove_unwanted_elements(doc)
    text = extract_content(doc)

    if text.length < MIN_CONTENT_LENGTH
      Rails.logger.warn "event=article_extraction_insufficient_content extracted_chars=#{text.length} min_required=#{MIN_CONTENT_LENGTH}"
      return Result.failure("Could not extract article content")
    end

    Rails.logger.info "event=article_extraction_success extracted_chars=#{text.length}"
    Result.success(text, title: extract_title(doc), author: extract_author(doc))
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
      return node if node && node.text.strip.length >= MIN_CONTENT_LENGTH
    end
    nil
  end

  def extract_title(doc)
    doc.at_css("title")&.text&.strip.presence
  end

  def extract_author(doc)
    doc.at_css('meta[name="author"]')&.[]("content")&.strip.presence
  end

  class Result
    attr_reader :text, :error, :title, :author

    def self.success(text, title: nil, author: nil)
      new(text: text, error: nil, title: title, author: author)
    end

    def self.failure(error)
      new(text: nil, error: error, title: nil, author: nil)
    end

    def initialize(text:, error:, title:, author:)
      @text = text
      @error = error
      @title = title
      @author = author
    end

    def success?
      error.nil?
    end

    def failure?
      !success?
    end

    def character_count
      text&.length || 0
    end
  end
end
