require "yaml"
require "fileutils"
require_relative "text_processor"
require_relative "tts"
require_relative "podcast_publisher"
require_relative "gcs_uploader"
require_relative "episode_manifest"

# Orchestrates episode processing from markdown to published podcast
# Reuses all existing infrastructure from generate.rb
class EpisodeProcessor
  attr_reader :bucket_name

  def initialize(bucket_name = nil)
    @bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET")
  end

  # Process an episode from start to finish
  # @param title [String] Episode title
  # @param author [String] Episode author
  # @param description [String] Episode description
  # @param markdown_content [String] Article body in markdown
  def process(title, author, description, markdown_content)
    print_start(title)
    filename = generate_filename(title)
    mp3_path = nil

    begin
      # Step 1: Convert markdown to plain text
      text = TextProcessor.convert_to_plain_text(markdown_content)

      # Step 2: Generate TTS audio
      tts = TTS.new
      audio_content = tts.synthesize(text)

      # Step 3: Save MP3 temporarily
      mp3_path = save_temp_mp3(filename, audio_content)

      # Step 4: Publish to podcast feed
      publish_to_feed(mp3_path, title, author, description)

      print_success(title)
    ensure
      # Always cleanup temporary file
      cleanup_temp_file(mp3_path) if mp3_path
    end
  end

  private

  def generate_filename(title)
    date = Time.now.strftime("%Y-%m-%d")
    slug = title.downcase
                .gsub(/[^\w\s-]/, "")  # Remove special chars
                .gsub(/\s+/, "-")      # Spaces to hyphens
                .gsub(/-+/, "-")       # Collapse multiple hyphens
                .strip
    "#{date}-#{slug}"
  end

  def save_temp_mp3(filename, audio_content)
    puts "\n[3/4] Saving temporary MP3..."

    FileUtils.mkdir_p("output")
    path = File.join("output", "#{filename}.mp3")
    File.write(path, audio_content, mode: "wb")

    puts "✓ Saved: #{mp3_path}"

    path
  end

  def publish_to_feed(mp3_path, title, author, description)
    puts "\n[4/4] Publishing to feed..."

    podcast_config = YAML.load_file("config/podcast.yml")
    gcs_uploader = GCSUploader.new(@bucket_name)
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
    puts "=" * 60
  end

  def print_success(title)
    puts "\n#{'=' * 60}"
    puts "✓ Complete: #{title}"
    puts "=" * 60
  end
end
