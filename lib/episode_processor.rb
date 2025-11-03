require "yaml"
require "fileutils"
require_relative "text_processor"
require_relative "tts"
require_relative "podcast_publisher"
require_relative "gcs_uploader"
require_relative "episode_manifest"
require_relative "filename_generator"

# Orchestrates episode processing from markdown to published podcast
# Reuses all existing infrastructure from generate.rb
class EpisodeProcessor
  attr_reader :bucket_name, :podcast_id

  def initialize(bucket_name = nil, podcast_id = nil)
    @bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET")
    @podcast_id = podcast_id

    raise ArgumentError, "podcast_id is required" unless @podcast_id

    validate_podcast_id_format!
  end

  # Process an episode from start to finish
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def process(title:, author:, description:, markdown_content:)
    print_start(title)

    # Step 1: Convert markdown to plain text
    text = TextProcessor.convert_to_plain_text(markdown_content)
    puts "✓ Converted to #{text.length} characters of plain text"

    # Step 2: Generate TTS audio
    puts "\n[2/3] Generating TTS audio..."
    tts = TTS.new
    audio_content = tts.synthesize(text)
    puts "✓ Generated #{format_size(audio_content.bytesize)} of audio"

    # Step 3: Publish to podcast feed (no temp file!)
    publish_to_feed(audio_content: audio_content, title: title, author: author, description: description)

    print_success(title)
  end

  private

  def publish_to_feed(audio_content:, title:, author:, description:)
    puts "\n[3/3] Publishing to feed..."

    podcast_config = YAML.safe_load_file("config/podcast.yml")
    gcs_uploader = GCSUploader.new(@bucket_name, podcast_id: @podcast_id)
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    publisher.publish(audio_content: audio_content, metadata: metadata(title: title, author: author,
                                                                       description: description))

    puts "✓ Published"
  end

  def metadata(title:, author:, description:)
    {
      "title" => title,
      "author" => author,
      "description" => description
    }
  end

  def format_size(bytes)
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1_048_576.0).round(1)} MB"
    end
  end

  def print_start(title)
    puts "=" * 60
    puts "Processing: #{title}"
    puts "Podcast ID: #{@podcast_id}"
    puts "=" * 60
  end

  def print_success(title)
    puts "\n#{'=' * 60}"
    puts "✓ Complete: #{title}"
    puts "Podcast ID: #{@podcast_id}"
    puts "=" * 60
  end

  def validate_podcast_id_format!
    # Format: podcast_{16 hex chars}
    # Example: podcast_a1b2c3d4e5f6a7b8
    format = /^podcast_[a-f0-9]{16}$/

    return if @podcast_id.match?(format)

    raise ArgumentError,
          "Invalid podcast_id format: '#{@podcast_id}'. " \
          "Expected format: podcast_{16 hex chars} (e.g., podcast_a1b2c3d4e5f6a7b8). " \
          "Generate with: openssl rand -hex 8"
  end
end
