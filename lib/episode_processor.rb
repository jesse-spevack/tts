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
    filename = FilenameGenerator.generate(title)
    mp3_path = nil

    begin
      # Step 1: Convert markdown to plain text
      text = TextProcessor.convert_to_plain_text(markdown_content)
      puts "✓ Converted to #{text.length} characters of plain text"

      # Step 2: Generate TTS audio
      puts "\n[2/4] Generating TTS audio..."
      tts = TTS.new
      audio_content = tts.synthesize(text)
      puts "✓ Generated #{format_size(audio_content.bytesize)} of audio"

      # Step 3: Save MP3 temporarily
      mp3_path = save_temp_mp3(filename, audio_content)

      # Step 4: Publish to podcast feed
      publish_to_feed(mp3_path: mp3_path, title: title, author: author, description: description)

      print_success(title)
    ensure
      # Always cleanup temporary file
      cleanup_temp_file(mp3_path) if mp3_path
    end
  end

  private

  def save_temp_mp3(filename, audio_content)
    puts "\n[3/4] Saving temporary MP3..."

    FileUtils.mkdir_p("output")
    path = File.join("output", "#{filename}.mp3")
    File.write(path, audio_content, mode: "wb")

    puts "✓ Saved: #{path}"

    path
  end

  def publish_to_feed(mp3_path:, title:, author:, description:)
    puts "\n[4/4] Publishing to feed..."

    podcast_config = YAML.safe_load_file("config/podcast.yml")
    gcs_uploader = GCSUploader.new(@bucket_name, podcast_id: @podcast_id)
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    publisher.publish(mp3_path, metadata(title: title, author: author, description: description))

    puts "✓ Published"
  end

  def metadata(title:, author:, description:)
    {
      "title" => title,
      "author" => author,
      "description" => description
    }
  end

  def cleanup_temp_file(path)
    FileUtils.rm_f(path)
    puts "✓ Cleaned up: #{path}"
  rescue StandardError => e
    puts "⚠ Cleanup warning: #{e.message}"
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
