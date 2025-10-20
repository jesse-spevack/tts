class TextProcessor
  class InvalidFileError < StandardError; end

  # Convert markdown file to plain text suitable for TTS
  # @param file [File, String] File object or file path
  # @return [String] Plain text content
  def self.markdown_to_text(file)
    validate_markdown(file)
    content = read_file(file)
    convert_to_plain_text(content)
  end

  private

  # Read file content from File object or path
  def self.read_file(file)
    if file.respond_to?(:read)
      file.read
    elsif file.is_a?(String)
      File.read(file)
    else
      raise ArgumentError, "Expected File object or String path, got #{file.class}"
    end
  end

  # Validate that the file is a markdown file
  def self.validate_markdown(file)
    filename = if file.respond_to?(:path)
                 file.path
               elsif file.is_a?(String)
                 file
               else
                 raise ArgumentError, "Cannot determine filename"
               end

    unless filename.end_with?('.md', '.markdown')
      raise InvalidFileError, "File must be a markdown file (.md or .markdown)"
    end
  end

  # Convert markdown content to plain text
  def self.convert_to_plain_text(content)
    text = content.dup

    # Remove code blocks (fenced with ``` or indented)
    text.gsub!(/```[\s\S]*?```/m, '')
    text.gsub!(/^\s{4,}.*$/, '')

    # Remove images ![alt](url)
    text.gsub!(/!\[([^\]]*)\]\([^\)]+\)/, '')

    # Convert links [text](url) to just text
    text.gsub!(/\[([^\]]+)\]\([^\)]+\)/, '\1')

    # Remove HTML tags
    text.gsub!(/<[^>]+>/, '')

    # Convert headers (remove # symbols)
    text.gsub!(/^[#]{1,6}\s+/, '')

    # Remove bold/italic markers
    text.gsub!(/(\*\*|__)(.*?)\1/, '\2')  # Bold
    text.gsub!(/(\*|_)(.*?)\1/, '\2')     # Italic

    # Remove strikethrough
    text.gsub!(/~~(.*?)~~/, '\1')

    # Convert unordered lists (-, *, +) to plain text
    text.gsub!(/^\s*[-*+]\s+/, '')

    # Convert ordered lists (1., 2., etc.) to plain text
    text.gsub!(/^\s*\d+\.\s+/, '')

    # Remove horizontal rules
    text.gsub!(/^(\*{3,}|-{3,}|_{3,})$/, '')

    # Remove blockquote markers
    text.gsub!(/^\s*>\s?/, '')

    # Remove inline code backticks
    text.gsub!(/`([^`]+)`/, '\1')

    # Clean up extra whitespace
    text.gsub!(/\n{3,}/, "\n\n")  # Multiple newlines to double newline
    text.strip!

    text
  end
end
