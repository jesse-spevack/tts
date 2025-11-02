class TextProcessor
  class InvalidFileError < StandardError; end

  def self.markdown_to_text(file)
    validate_markdown(file)
    content = read_file(file)
    convert_to_plain_text(content)
  end

  def self.read_file(file)
    if file.respond_to?(:read)
      file.read
    elsif file.is_a?(String)
      File.read(file)
    else
      raise ArgumentError, "Expected File object or String path, got #{file.class}"
    end
  end

  def self.validate_markdown(file)
    filename = if file.respond_to?(:path)
                 file.path
               elsif file.is_a?(String)
                 file
               else
                 raise ArgumentError, "Cannot determine filename"
               end

    return if filename.end_with?(".md", ".markdown")

    raise InvalidFileError, "File must be a markdown file (.md or .markdown)"
  end

  def self.convert_to_plain_text(content)
    puts "\n[1/4] Processing markdown..."

    text = content.dup

    text = TextConverter.remove_yaml_frontmatter(text)
    text = TextConverter.remove_code_blocks(text)
    text = TextConverter.remove_images(text)
    text = TextConverter.convert_links(text)
    text = TextConverter.remove_html_tags(text)
    text = TextConverter.remove_headers(text)
    text = TextConverter.remove_formatting(text)
    text = TextConverter.remove_strikethrough(text)
    text = TextConverter.remove_unordered_lists(text)
    text = TextConverter.remove_ordered_lists(text)
    text = TextConverter.remove_horizontal_rules(text)
    text = TextConverter.remove_blockquotes(text)
    text = TextConverter.remove_inline_code(text)
    text = TextConverter.clean_whitespace(text)

    puts "✓ Processed #{text.length} characters"

    text
  end
end
