require "minitest/autorun"
require "tempfile"
require_relative "../lib/metadata_extractor"

class TestMetadataExtractor < Minitest::Test
  def test_extracts_valid_frontmatter
    markdown = <<~MD
      ---
      title: "My Episode Title"
      description: "This is an episode description"
      author: "John Doe"
      ---

      # Episode Content

      This is the actual content.
    MD

    file = create_temp_file(markdown)
    metadata = MetadataExtractor.extract(file.path)

    assert_equal "My Episode Title", metadata[:title]
    assert_equal "This is an episode description", metadata[:description]
    assert_equal "John Doe", metadata[:author]

    file.unlink
  end

  def test_extracts_frontmatter_without_optional_author
    markdown = <<~MD
      ---
      title: "Episode Without Author"
      description: "Testing optional fields"
      ---

      Content here.
    MD

    file = create_temp_file(markdown)
    metadata = MetadataExtractor.extract(file.path)

    assert_equal "Episode Without Author", metadata[:title]
    assert_equal "Testing optional fields", metadata[:description]
    assert_nil metadata[:author]

    file.unlink
  end

  def test_raises_error_when_title_missing
    markdown = <<~MD
      ---
      description: "Has description but no title"
      ---

      Content.
    MD

    file = create_temp_file(markdown)

    error = assert_raises(MetadataExtractor::MissingRequiredFieldError) do
      MetadataExtractor.extract(file.path)
    end

    assert_match(/title/i, error.message)

    file.unlink
  end

  def test_raises_error_when_description_missing
    markdown = <<~MD
      ---
      title: "Has title but no description"
      ---

      Content.
    MD

    file = create_temp_file(markdown)

    error = assert_raises(MetadataExtractor::MissingRequiredFieldError) do
      MetadataExtractor.extract(file.path)
    end

    assert_match(/description/i, error.message)

    file.unlink
  end

  def test_raises_error_when_both_title_and_description_missing
    markdown = <<~MD
      ---
      author: "Only Author"
      ---

      Content.
    MD

    file = create_temp_file(markdown)

    error = assert_raises(MetadataExtractor::MissingRequiredFieldError) do
      MetadataExtractor.extract(file.path)
    end

    assert_match(/title/, error.message)

    file.unlink
  end

  def test_raises_error_with_invalid_yaml
    markdown = <<~MD
      ---
      title: "Valid Title
      description: Missing closing quote
      ---

      Content.
    MD

    file = create_temp_file(markdown)

    assert_raises(MetadataExtractor::InvalidFrontmatterError) do
      MetadataExtractor.extract(file.path)
    end

    file.unlink
  end

  def test_raises_error_when_no_frontmatter
    markdown = <<~MD
      # Just a regular markdown file

      No frontmatter here.
    MD

    file = create_temp_file(markdown)

    assert_raises(MetadataExtractor::MissingFrontmatterError) do
      MetadataExtractor.extract(file.path)
    end

    file.unlink
  end

  def test_handles_frontmatter_with_extra_fields
    markdown = <<~MD
      ---
      title: "Episode Title"
      description: "Episode description"
      author: "Jane Smith"
      publish_date: "2025-10-26"
      custom_field: "Ignored"
      ---

      Content.
    MD

    file = create_temp_file(markdown)
    metadata = MetadataExtractor.extract(file.path)

    assert_equal "Episode Title", metadata[:title]
    assert_equal "Episode description", metadata[:description]
    assert_equal "Jane Smith", metadata[:author]
    # Extra fields should be ignored, not cause errors

    file.unlink
  end


  def test_trims_whitespace_from_fields
    markdown = <<~MD
      ---
      title: "  Title with spaces  "
      description: "  Description with spaces  "
      author: "  Author Name  "
      ---

      Content.
    MD

    file = create_temp_file(markdown)
    metadata = MetadataExtractor.extract(file.path)

    assert_equal "Title with spaces", metadata[:title]
    assert_equal "Description with spaces", metadata[:description]
    assert_equal "Author Name", metadata[:author]

    file.unlink
  end

  private

  def create_temp_file(content)
    file = Tempfile.new(["test", ".md"])
    file.write(content)
    file.close
    file
  end
end
