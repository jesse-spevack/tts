require "minitest/autorun"
require_relative "../lib/filename_generator"

class TestFilenameGenerator < Minitest::Test
  def test_generate_includes_date_and_slug
    filename = FilenameGenerator.generate("Test Episode Title")

    assert_match(/^\d{4}-\d{2}-\d{2}-test-episode-title$/, filename)
  end

  def test_generate_removes_special_chars
    filename = FilenameGenerator.generate("Test (Special) Chars!")

    assert_match(/test-special-chars$/, filename)
  end

  def test_generate_converts_to_lowercase
    filename = FilenameGenerator.generate("UPPERCASE TITLE")

    assert_match(/uppercase-title$/, filename)
  end

  def test_generate_replaces_spaces_with_hyphens
    filename = FilenameGenerator.generate("Multiple Word Title")

    assert_match(/multiple-word-title$/, filename)
  end

  def test_generate_collapses_multiple_hyphens
    filename = FilenameGenerator.generate("Title---With---Hyphens")

    assert_match(/title-with-hyphens$/, filename)
  end

  def test_generate_strips_leading_and_trailing_whitespace
    filename = FilenameGenerator.generate("  Title With Spaces  ")

    assert_match(/title-with-spaces$/, filename)
  end

  def test_generate_handles_emoji_and_unicode
    filename = FilenameGenerator.generate("Title with 🚀 emoji")

    assert_match(/title-with-emoji$/, filename)
  end
end
