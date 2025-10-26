require "yaml"

class MetadataExtractor
  class MissingFrontmatterError < StandardError; end
  class InvalidFrontmatterError < StandardError; end
  class MissingRequiredFieldError < StandardError; end

  # Extract metadata from markdown file frontmatter
  # @param file_path [String] Path to markdown file
  # @return [Hash] Hash with :title, :description, and optional :author
  def self.extract(file_path)
    content = File.read(file_path)
    frontmatter = parse_frontmatter(content)
    validate_and_normalize(frontmatter)
  end

  # Parse YAML frontmatter from markdown content
  def self.parse_frontmatter(content)
    # Match frontmatter between --- delimiters at the start of the file
    match = content.match(/\A---\s*\n(.*?\n)---\s*\n/m)

    raise MissingFrontmatterError, "No frontmatter found in markdown file" unless match

    yaml_content = match[1]

    begin
      YAML.safe_load(yaml_content)
    rescue Psych::SyntaxError => e
      raise InvalidFrontmatterError, "Invalid YAML in frontmatter: #{e.message}"
    end
  end

  # Validate required fields and normalize the metadata hash
  def self.validate_and_normalize(frontmatter)
    raise MissingRequiredFieldError, "Missing required field: title" unless frontmatter["title"]
    raise MissingRequiredFieldError, "Missing required field: description" unless frontmatter["description"]

    {
      title: frontmatter["title"].to_s.strip,
      description: frontmatter["description"].to_s.strip,
      author: frontmatter["author"]&.to_s&.strip
    }
  end
end
