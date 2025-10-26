#!/usr/bin/env ruby

require "dotenv/load"
require "optparse"
require_relative "lib/text_processor"
require_relative "lib/tts"

# Parse command-line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby generate.rb [options] INPUT_FILE"

  opts.on("-p", "--provider PROVIDER", "TTS provider (google, open_ai, eleven_labs)") do |p|
    options[:provider] = p.to_sym
  end

  opts.on("-v", "--voice VOICE", "Voice name (default: en-GB-Chirp3-HD-Enceladus)") do |v|
    options[:voice] = v
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
options[:provider] ||= :google
options[:voice] ||= "en-GB-Chirp3-HD-Enceladus"

puts "=" * 60
puts "Text-to-Speech Generator"
puts "=" * 60
puts "Input file: #{input_file}"
puts "Provider: #{options[:provider]}"
puts "Voice: #{options[:voice]}"
puts "=" * 60

# Step 1: Read and process markdown
puts "\n[1/3] Processing markdown file..."
begin
  text = TextProcessor.markdown_to_text(input_file)
  puts "✓ Converted markdown to plain text"
  puts "  Text length: #{text.length} characters"
rescue ArgumentError => e
  puts "✗ Error: #{e.message}"
  exit 1
end

# Step 2: Generate audio
puts "\n[2/3] Generating audio with #{options[:provider]}..."
begin
  tts = TTS.new(provider: options[:provider])
  audio_content = tts.synthesize(text, voice: options[:voice])
  puts "✓ Audio generated successfully"
  puts "  Audio size: #{audio_content.bytesize} bytes"
rescue StandardError => e
  puts "✗ Error generating audio: #{e.message}"
  exit 1
end

# Step 3: Save to output directory
puts "\n[3/3] Saving audio file..."
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

puts "\n#{'=' * 60}"
puts "✓ SUCCESS! Audio file generated successfully"
puts "=" * 60
puts "\nTo play the audio:"
puts "  open #{output_file}"
