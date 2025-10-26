#!/usr/bin/env ruby

require "dotenv/load"
require_relative "lib/text_processor"
require_relative "lib/tts"

puts "Testing single chunk with Flash model..."
puts "=" * 60

# Read the article
input_file = "input/2025-10-25-window-into-modern-loan-origination.md"
text = TextProcessor.markdown_to_text(input_file)

# Get just the first chunk
tts = TTS.new
chunks = tts.send(:chunk_text, text, 850)

puts "Total chunks available: #{chunks.length}"
puts "Testing with first chunk only (#{chunks[0].bytesize} bytes)"
puts "Preview: #{chunks[0][0..100]}..."
puts ""

# Time it
start_time = Time.now
audio = tts.synthesize(chunks[0])
duration = Time.now - start_time

puts ""
puts "✓ Success!"
puts "  Processing time: #{duration.round(2)}s"
puts "  Audio size: #{audio.bytesize} bytes"
puts "  Audio size: #{(audio.bytesize / 1024.0).round(1)} KB"

# Save it
output_file = "output/test_single_chunk.mp3"
File.write(output_file, audio, mode: "wb")
puts "  Saved to: #{output_file}"
