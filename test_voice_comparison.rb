#!/usr/bin/env ruby

require "dotenv/load"
require_relative "lib/text_processor"
require_relative "lib/tts"
require_relative "lib/metadata_extractor"

# Test the smallest input file
INPUT_FILE = "input/2025-10-26-workslop-was-the-logical-outcome-of-productivity-maxxing.md"

# Voice configurations
CHIRP_VOICE = "en-GB-Chirp3-HD-Enceladus"
NEURAL2_VOICE = "en-GB-Neural2-B"  # Closest equivalent - British male

puts "=" * 70
puts "TTS Voice Comparison: Chirp3-HD vs Neural2"
puts "=" * 70
puts "Input file: #{INPUT_FILE}"
puts "File size: #{File.size(INPUT_FILE)} bytes"
puts

# Extract metadata and text
metadata = MetadataExtractor.extract(INPUT_FILE)
text = TextProcessor.markdown_to_text(INPUT_FILE)

puts "Title: #{metadata[:title]}"
puts "Text length: #{text.length} characters"
puts

# Calculate costs
chirp_cost = (text.length / 1_000_000.0) * 30  # $30 per 1M chars
neural2_cost = (text.length / 1_000_000.0) * 16  # $16 per 1M chars
standard_cost = (text.length / 1_000_000.0) * 4   # $4 per 1M chars (for reference)

puts "Cost comparison for this episode:"
puts "  Chirp3-HD:  $#{'%.4f' % chirp_cost} ($30/1M chars)"
puts "  Neural2:    $#{'%.4f' % neural2_cost} ($16/1M chars) - 47% cheaper"
puts "  Standard:   $#{'%.4f' % standard_cost} ($4/1M chars)  - 87% cheaper"
puts

# Generate audio with both voices
tts = TTS.new

puts "-" * 70
puts "Generating with Chirp3-HD (#{CHIRP_VOICE})..."
puts "-" * 70
start_time = Time.now
chirp_audio = tts.synthesize(text, voice: CHIRP_VOICE)
chirp_duration = Time.now - start_time
chirp_output = "output/test_chirp3hd.mp3"
File.write(chirp_output, chirp_audio, mode: "wb")
chirp_size_kb = (chirp_audio.bytesize / 1024.0).round(1)

puts "✓ Chirp3-HD complete"
puts "  Processing time: #{chirp_duration.round(1)}s"
puts "  File size: #{chirp_size_kb} KB"
puts "  Output: #{chirp_output}"
puts

puts "-" * 70
puts "Generating with Neural2 (#{NEURAL2_VOICE})..."
puts "-" * 70
start_time = Time.now
neural2_audio = tts.synthesize(text, voice: NEURAL2_VOICE)
neural2_duration = Time.now - start_time
neural2_output = "output/test_neural2.mp3"
File.write(neural2_output, neural2_audio, mode: "wb")
neural2_size_kb = (neural2_audio.bytesize / 1024.0).round(1)

puts "✓ Neural2 complete"
puts "  Processing time: #{neural2_duration.round(1)}s"
puts "  File size: #{neural2_size_kb} KB"
puts "  Output: #{neural2_output}"
puts

puts "=" * 70
puts "Comparison Summary"
puts "=" * 70
puts
puts "Quality:"
puts "  Chirp3-HD: Premium quality, most natural"
puts "  Neural2:   High quality, very natural"
puts
puts "Cost:"
puts "  Chirp3-HD: $#{'%.4f' % chirp_cost}"
puts "  Neural2:   $#{'%.4f' % neural2_cost} (47% savings)"
puts "  Savings:   $#{'%.4f' % (chirp_cost - neural2_cost)}"
puts
puts "Files saved to:"
puts "  Chirp3-HD: #{chirp_output}"
puts "  Neural2:   #{neural2_output}"
puts
puts "To listen and compare:"
puts "  open #{chirp_output}"
puts "  open #{neural2_output}"
puts
puts "=" * 70
