# frozen_string_literal: true

class ConvertsTwitterArticleBlocks
  def self.call(blocks:)
    new(blocks: blocks).call
  end

  def initialize(blocks:)
    @blocks = blocks
  end

  def call
    return nil unless blocks.is_a?(Array) && blocks.any?

    title = extract_title
    text = blocks_to_text
    return nil if text.blank?

    ExtractsArticle::ArticleData.new(text: text, title: title, author: nil)
  end

  private

  attr_reader :blocks

  def extract_title
    first_block = blocks.first
    return nil unless first_block

    first_block["text"] if first_block["type"]&.start_with?("header")
  end

  def blocks_to_text
    blocks.filter_map { |block|
      text = block["text"]
      next if text.blank?

      case block["type"]
      when "header-one"
        "# #{text}"
      when "header-two"
        "## #{text}"
      when "header-three"
        "### #{text}"
      else
        text
      end
    }.join("\n\n")
  end
end
