require 'minitest/autorun'
require_relative '../lib/text_processor'

class TestTextProcessor < Minitest::Test
  def test_removes_headers
    markdown = "# Heading 1\n## Heading 2\n### Heading 3"
    expected = "Heading 1\nHeading 2\nHeading 3"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_bold
    markdown = "This is **bold** text"
    expected = "This is bold text"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_italic
    markdown = "This is *italic* text"
    expected = "This is italic text"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_bold_with_underscores
    markdown = "This is __bold__ text"
    expected = "This is bold text"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_italic_with_underscores
    markdown = "This is _italic_ text"
    expected = "This is italic text"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_converts_links_to_text
    markdown = "Check out [this link](https://example.com)"
    expected = "Check out this link"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_images
    markdown = "Here's an image: ![alt text](https://example.com/image.png)"
    expected = "Here's an image:"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_code_blocks
    markdown = "Some text\n```ruby\ndef hello\n  puts 'hi'\nend\n```\nMore text"
    result = TextProcessor.convert_to_plain_text(markdown)
    assert_equal "Some text\n\nMore text", result
  end

  def test_removes_inline_code
    markdown = "Use the `print` function"
    expected = "Use the print function"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_unordered_list_markers
    markdown = "- Item 1\n- Item 2\n* Item 3\n+ Item 4"
    expected = "Item 1\nItem 2\nItem 3\nItem 4"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_ordered_list_markers
    markdown = "1. First\n2. Second\n3. Third"
    expected = "First\nSecond\nThird"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_blockquotes
    markdown = "> This is a quote\n> Second line"
    expected = "This is a quote\nSecond line"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_horizontal_rules
    markdown = "Text above\n---\nText below"
    result = TextProcessor.convert_to_plain_text(markdown)
    refute_includes result, "---"
  end

  def test_removes_strikethrough
    markdown = "This is ~~strikethrough~~ text"
    expected = "This is strikethrough text"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_removes_html_tags
    markdown = "This is <strong>HTML</strong> text"
    expected = "This is HTML text"
    assert_equal expected, TextProcessor.convert_to_plain_text(markdown)
  end

  def test_complex_markdown
    markdown = <<~MD
      # My Blog Post

      This is a **great** article about *programming*.

      ## Features

      - Easy to use
      - Fast
      - Reliable

      Check out [the documentation](https://example.com) for more info.

      ```ruby
      def example
        puts "code"
      end
      ```

      > Remember: always test your code!
    MD

    result = TextProcessor.convert_to_plain_text(markdown)

    assert_includes result, "My Blog Post"
    assert_includes result, "great"
    assert_includes result, "programming"
    assert_includes result, "Easy to use"
    refute_includes result, "**"
    refute_includes result, "*"
    refute_includes result, "```"
    refute_includes result, "def example"
  end

  def test_validates_markdown_file_extension
    error = assert_raises(TextProcessor::InvalidFileError) do
      TextProcessor.markdown_to_text("test.txt")
    end
    assert_match(/must be a markdown file/, error.message)
  end

  def test_reads_from_file_path
    # Create a temporary markdown file
    require 'tempfile'
    file = Tempfile.new(['test', '.md'])
    file.write("# Hello World")
    file.close

    result = TextProcessor.markdown_to_text(file.path)
    assert_equal "Hello World", result

    file.unlink
  end

  def test_reads_from_file_object
    require 'tempfile'
    file = Tempfile.new(['test', '.md'])
    file.write("# Hello from File")
    file.rewind

    result = TextProcessor.markdown_to_text(file)
    assert_equal "Hello from File", result

    file.close
    file.unlink
  end
end
