require "minitest/autorun"
require_relative "../lib/text_converter"

class TestTextConverter < Minitest::Test
  def test_remove_yaml_frontmatter
    result = TextConverter.remove_yaml_frontmatter(yaml_frontmatter_text)

    refute_includes result, "title:"
    refute_includes result, "author:"
    assert_includes result, "Content here"
  end

  def test_remove_code_blocks_fenced
    text = "Before\n```ruby\ndef hello\n  'world'\nend\n```\nAfter"
    result = TextConverter.remove_code_blocks(text)

    assert_includes result, "Before"
    assert_includes result, "After"
    refute_includes result, "def hello"
    refute_includes result, "```"
  end

  def test_remove_code_blocks_indented
    text = "Before\n    indented code\n    more code\nAfter"
    result = TextConverter.remove_code_blocks(text)

    assert_includes result, "Before"
    assert_includes result, "After"
    refute_includes result, "indented code"
  end

  def test_remove_images
    text = "Check this ![cat photo](https://example.com/cat.jpg) out"
    result = TextConverter.remove_images(text)

    assert_equal "Check this  out", result
    refute_includes result, "cat photo"
  end

  def test_convert_links
    text = "Visit [my site](https://example.com) today"
    result = TextConverter.convert_links(text)

    assert_equal "Visit my site today", result
    refute_includes result, "["
  end

  def test_remove_html_tags
    text = "This is <strong>bold</strong> and <em>italic</em>"
    result = TextConverter.remove_html_tags(text)

    assert_equal "This is bold and italic", result
    refute_includes result, "<strong>"
  end

  def test_remove_headers
    text = "# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6"
    result = TextConverter.remove_headers(text)

    assert_equal "H1\nH2\nH3\nH4\nH5\nH6", result
    refute_includes result, "#"
  end

  def test_remove_formatting_bold
    assert_equal "This is bold text", TextConverter.remove_formatting("This is **bold** text")
    assert_equal "This is bold text", TextConverter.remove_formatting("This is __bold__ text")
  end

  def test_remove_formatting_italic
    assert_equal "This is italic text", TextConverter.remove_formatting("This is *italic* text")
    assert_equal "This is italic text", TextConverter.remove_formatting("This is _italic_ text")
  end

  def test_remove_strikethrough
    text = "This is ~~deleted~~ text"
    result = TextConverter.remove_strikethrough(text)

    assert_equal "This is deleted text", result
    refute_includes result, "~~"
  end

  def test_remove_unordered_lists
    text = "- Item 1\n* Item 2\n+ Item 3"
    result = TextConverter.remove_unordered_lists(text)

    assert_equal "Item 1\nItem 2\nItem 3", result
  end

  def test_remove_ordered_lists
    text = "1. First\n2. Second\n10. Tenth"
    result = TextConverter.remove_ordered_lists(text)

    assert_equal "First\nSecond\nTenth", result
  end

  def test_remove_horizontal_rules
    result = TextConverter.remove_horizontal_rules("Above\n---\nBelow")
    assert_includes result, "Above"
    assert_includes result, "Below"

    result = TextConverter.remove_horizontal_rules("Above\n***\nBelow")
    refute_match(/^\*\*\*$/, result)

    result = TextConverter.remove_horizontal_rules("Above\n___\nBelow")
    refute_match(/^___$/, result)
  end

  def test_remove_blockquotes
    text = "> Quote line 1\n> Quote line 2"
    result = TextConverter.remove_blockquotes(text)

    assert_equal "Quote line 1\nQuote line 2", result
    refute_includes result, ">"
  end

  def test_remove_inline_code
    text = "Use the `print` function here"
    result = TextConverter.remove_inline_code(text)

    assert_equal "Use the print function here", result
    refute_includes result, "`"
  end

  def test_clean_whitespace
    assert_equal "Line 1\n\nLine 2", TextConverter.clean_whitespace("Line 1\n\n\n\nLine 2")
    assert_equal "Text here", TextConverter.clean_whitespace("\n\n  Text here  \n\n")
  end

  private

  def yaml_frontmatter_text
    <<~TEXT
      ---
      title: "My Post"
      author: "John"
      ---
      Content here
    TEXT
  end
end
