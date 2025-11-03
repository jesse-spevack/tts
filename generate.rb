#!/usr/bin/env ruby

require "dotenv/load"
require "optparse"
require "yaml"
require_relative "lib/text_processor"
require_relative "lib/tts"
require_relative "lib/metadata_extractor"
require_relative "lib/gcs_uploader"
require_relative "lib/episode_manifest"
require_relative "lib/rss_generator"
require_relative "lib/podcast_publisher"
require_relative "lib/podcast_id_validator"

# Parse command-line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby generate.rb [options] INPUT_FILE"

  opts.on("-v", "--voice VOICE", "Voice name (default: en-GB-Chirp3-HD-Enceladus)") do |v|
    options[:voice] = v
  end

  opts.on("-l", "--local-only", "Generate MP3 locally without publishing to podcast feed") do
    options[:local_only] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate input file
if ARGV.empty?
  puts "Error: No input file specified"
  puts "Usage: ruby generate.rb [options] INPUT_FILE"
  exit 1
end

input_file = ARGV[0]

unless File.exist?(input_file)
  puts "Error: File not found: #{input_file}"
  exit 1
end

# Set defaults
options[:voice] ||= "en-GB-Chirp3-HD-Enceladus"

puts "=" * 60
puts "Text-to-Speech Podcast Generator"
puts "=" * 60
puts "Input file: #{input_file}"
puts "Voice: #{options[:voice]}"
puts "Mode: #{options[:local_only] ? 'Local only' : 'Publish to podcast feed'}"
puts "=" * 60

# Step 1: Extract metadata from frontmatter
puts "\n[1/#{options[:local_only] ? 3 : 5}] Extracting metadata..."
begin
  metadata = MetadataExtractor.extract(input_file)
  puts "✓ Metadata extracted"
  puts "  Title: #{metadata[:title]}"
  puts "  Description: #{metadata[:description]}"
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  exit 1
end

# Step 2: Read and process markdown
puts "\n[2/#{options[:local_only] ? 3 : 5}] Processing markdown file..."
begin
  text = TextProcessor.markdown_to_text(input_file)
  puts "✓ Converted markdown to plain text"
  puts "  Text length: #{text.length} characters"
rescue ArgumentError => e
  puts "✗ Error: #{e.message}"
  exit 1
end

# Step 3: Generate audio
puts "\n[3/#{options[:local_only] ? 3 : 5}] Generating audio..."
begin
  tts = TTS.new
  audio_content = tts.synthesize(text, voice: options[:voice])
  puts "✓ Audio generated successfully"
  puts "  Audio size: #{audio_content.bytesize} bytes"
rescue StandardError => e
  puts "✗ Error generating audio: #{e.message}"
  exit 1
end

# Step 4: Save to output directory
puts "\n[#{options[:local_only] ? 3 : 4}/#{options[:local_only] ? 3 : 5}] Saving audio file..."
begin
  # Generate output filename from input filename
  basename = File.basename(input_file, File.extname(input_file))
  output_file = File.join("output", "#{basename}.mp3")

  File.write(output_file, audio_content, mode: "wb")
  puts "✓ Audio saved to: #{output_file}"

  # Show file info
  file_size_kb = (File.size(output_file) / 1024.0).round(1)
  puts "  File size: #{file_size_kb} KB"
rescue StandardError => e
  puts "✗ Error saving file: #{e.message}"
  exit 1
end

# Step 5: Publish to podcast feed (unless --local-only)
unless options[:local_only]
  puts "\n[5/5] Publishing to podcast feed..."
  begin
    # Load podcast config
    podcast_config = YAML.safe_load_file("config/podcast.yml")

    # Initialize GCS and manifest
    podcast_id = ENV.fetch("PODCAST_ID") do
      raise "PODCAST_ID environment variable is required. " \
            "Generate with: echo \"PODCAST_ID=podcast_$(openssl rand -hex 8)\" >> .env"
    end

    # Validate podcast_id format
    PodcastIdValidator.validate!(podcast_id)

    gcs_uploader = GCSUploader.new(ENV.fetch("GOOGLE_CLOUD_BUCKET", nil), podcast_id: podcast_id)
    episode_manifest = EpisodeManifest.new(gcs_uploader)

    # Publish episode
    publisher = PodcastPublisher.new(
      podcast_config: podcast_config,
      gcs_uploader: gcs_uploader,
      episode_manifest: episode_manifest
    )

    # Convert symbol keys to string keys for publisher
    metadata_with_string_keys = metadata.transform_keys(&:to_s)
    feed_url = publisher.publish(audio_content: audio_content, metadata: metadata_with_string_keys)

    puts "✓ Episode published successfully"
    puts "  Podcast ID: #{podcast_id}"
    puts "  Feed URL: #{feed_url}"
    puts "  Episodes in feed: #{episode_manifest.episodes.length}"
  rescue StandardError => e
    puts "✗ Error publishing episode: #{e.message}"
    puts "  Local MP3 file saved successfully at: #{output_file}"
    exit 1
  end
end

puts "\n#{'=' * 60}"
puts "✓ SUCCESS! #{options[:local_only] ? 'Audio file generated' : 'Episode published'} successfully"
puts "=" * 60
if options[:local_only]
  puts "\nTo play the audio:"
  puts "  open #{output_file}"
else
  puts "\nYour podcast feed is live!"
  puts "Subscribe in your podcast app with the feed URL above."
end
