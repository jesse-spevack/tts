# frozen_string_literal: true

# Generate voice samples for the settings page audio preview
#
# Usage:
#   cd hub && ruby ../scripts/generate_voice_samples.rb
#
# Prerequisites:
#   - GOOGLE_CLOUD_PROJECT environment variable set
#   - Google Cloud credentials configured
#
# After running:
#   gsutil cp tmp/*.mp3 gs://YOUR_BUCKET/voices/

require "fileutils"
require "google/cloud/text_to_speech"

SAMPLE_TEXT = "New research suggests that listening to articles can improve comprehension and retention, especially during commutes."

VOICES = {
  # Standard voices (free/premium)
  "wren"    => "en-GB-Standard-C",
  "felix"   => "en-GB-Standard-D",
  "sloane"  => "en-US-Standard-C",
  "archer"  => "en-US-Standard-J",
  "gemma"   => "en-GB-Standard-A",
  "hugo"    => "en-GB-Standard-B",
  "quinn"   => "en-US-Standard-E",
  "theo"    => "en-US-Standard-D",
  # Chirp voices (unlimited)
  "elara"   => "en-GB-Chirp3-HD-Gacrux",
  "callum"  => "en-GB-Chirp3-HD-Enceladus",
  "lark"    => "en-US-Chirp3-HD-Callirrhoe",
  "nash"    => "en-US-Chirp3-HD-Charon"
}.freeze

client = Google::Cloud::TextToSpeech.text_to_speech

FileUtils.mkdir_p("tmp")

VOICES.each do |name, google_voice|
  puts "Generating #{name}..."

  language_code = google_voice.start_with?("en-GB") ? "en-GB" : "en-US"

  response = client.synthesize_speech(
    input: { text: SAMPLE_TEXT },
    voice: { language_code: language_code, name: google_voice },
    audio_config: { audio_encoding: "MP3" }
  )

  File.binwrite("tmp/#{name}.mp3", response.audio_content)
  puts "  Saved to tmp/#{name}.mp3"
end

puts "Done! Upload files to gs://YOUR_BUCKET/voices/"
