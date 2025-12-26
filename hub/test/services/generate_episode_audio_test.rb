# frozen_string_literal: true

require "test_helper"

class GenerateEpisodeAudioTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:pending)
    @episode.update!(source_text: "Hello, this is a test episode.")

    Mocktail.replace(Tts::Synthesizer)
    Mocktail.replace(GcsUploader)
  end

  test "synthesizes audio and updates episode" do
    mock_synthesizer = Mocktail.of(Tts::Synthesizer)
    stubs { |m| mock_synthesizer.synthesize(m.any, voice: m.any) }.with { "fake audio content" }
    stubs { |m| Tts::Synthesizer.new(config: m.any) }.with { mock_synthesizer }

    mock_gcs = Mocktail.of(GcsUploader)
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| GcsUploader.new(podcast_id: m.any) }.with { mock_gcs }

    GenerateEpisodeAudio.call(episode: @episode, skip_feed_upload: true)

    @episode.reload
    assert_equal "complete", @episode.status
    assert_not_nil @episode.gcs_episode_id
  end

  test "marks episode as failed on error" do
    mock_synthesizer = Mocktail.of(Tts::Synthesizer)
    stubs { |m| mock_synthesizer.synthesize(m.any, voice: m.any) }.with { raise StandardError, "TTS API error" }
    stubs { |m| Tts::Synthesizer.new(config: m.any) }.with { mock_synthesizer }

    GenerateEpisodeAudio.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "TTS API error", @episode.error_message
  end
end
