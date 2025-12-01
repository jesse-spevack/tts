class ArticleExtractor
  REMOVE_TAGS = %w[script style nav footer header aside form noscript iframe].freeze
  CONTENT_SELECTORS = %w[article main body].freeze
  MIN_CONTENT_LENGTH = 100

  def self.call(html:)
    new(html: html).call
  end

  def initialize(html:)
    @html = html
  end

  def call
    doc = Nokogiri::HTML(html)
    remove_unwanted_elements(doc)
    text = extract_content(doc)

    return Result.failure("Could not extract article content") if text.length < MIN_CONTENT_LENGTH

    Result.success(text)
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

  class Result
    attr_reader :text, :error

    def self.success(text)
      new(text: text, error: nil)
    end

    def self.failure(error)
      new(text: nil, error: error)
    end

    def initialize(text:, error:)
      @text = text
      @error = error
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
