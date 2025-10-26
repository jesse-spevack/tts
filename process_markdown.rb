#!/usr/bin/env ruby

require_relative "lib/text_processor"

if ARGV.empty?
  puts "Usage: ruby process_markdown.rb <markdown_file>"
  exit 1
end

file_path = ARGV[0]

begin
  text = TextProcessor.markdown_to_text(file_path)
  puts "=== Converted Text ==="
  puts text
  puts "\n=== Stats ==="
  puts "Characters: #{text.length}"
  puts "Words: #{text.split.length}"
rescue StandardError => e
  puts "Error: #{e.message}"
  exit 1
end
