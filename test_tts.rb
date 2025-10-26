#!/usr/bin/env ruby

require "dotenv/load"
require_relative "lib/tts"

# Test the TTS module with a short sample
puts "Testing Google Cloud TTS..."

# Initialize TTS with Google provider
tts = TTS.new(provider: :google)

# Test text
test_text = "Hello! This is a test of the Ruby TTS module using Google Cloud Text to Speech."

puts "Synthesizing: #{test_text}"

# Generate audio
audio_content = tts.synthesize(test_text)

# Save to output directory
output_file = "output/test.mp3"
File.write(output_file, audio_content, mode: "wb")

puts "Audio saved to: #{output_file}"
puts "File size: #{File.size(output_file)} bytes"
puts "Test complete!"
