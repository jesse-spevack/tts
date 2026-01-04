# frozen_string_literal: true

require "test_helper"

class GeneratesEpisodeAudioTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:pending)
    @episode.update!(source_text: "Hello, this is a test episode.")

    Mocktail.replace(SynthesizesAudio)
    Mocktail.replace(CloudStorage)
  end

  test "synthesizes audio and updates episode" do
    mock_synthesizer = Mocktail.of(SynthesizesAudio)
    stubs { |m| mock_synthesizer.call(text: m.any, voice: m.any) }.with { "fake audio content" }
    stubs { |m| SynthesizesAudio.new(config: m.any) }.with { mock_synthesizer }

    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }

    GeneratesEpisodeAudio.call(episode: @episode, skip_feed_upload: true)

    @episode.reload
    assert_equal "complete", @episode.status
    assert_not_nil @episode.gcs_episode_id
  end

  test "marks episode as failed on error" do
    mock_synthesizer = Mocktail.of(SynthesizesAudio)
    stubs { |m| mock_synthesizer.call(text: m.any, voice: m.any) }.with { raise StandardError, "TTS API error" }
    stubs { |m| SynthesizesAudio.new(config: m.any) }.with { mock_synthesizer }

    GeneratesEpisodeAudio.call(episode: @episode)

    @episode.reload
    assert_equal "failed", @episode.status
    assert_equal "TTS API error", @episode.error_message
  end

  test "cleans up uploaded audio if episode update fails" do
    mock_synthesizer = Mocktail.of(SynthesizesAudio)
    stubs { |m| mock_synthesizer.call(text: m.any, voice: m.any) }.with { "fake audio content" }
    stubs { |m| SynthesizesAudio.new(config: m.any) }.with { mock_synthesizer }

    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }

    # Make episode update fail when trying to mark as complete
    @episode.define_singleton_method(:update!) do |**attrs|
      if attrs[:status] == :complete
        raise ActiveRecord::RecordInvalid.new(self)
      end
      super(**attrs)
    end

    GeneratesEpisodeAudio.call(episode: @episode, skip_feed_upload: true)

    # Verify cleanup was attempted - delete_file should have been called
    delete_calls = Mocktail.calls(mock_gcs, :delete_file)
    assert_equal 1, delete_calls.size

    # Episode should be marked as failed
    # Need to reload via unscoped since we're using a singleton method
    episode = Episode.unscoped.find(@episode.id)
    assert_equal "failed", episode.status
  end
end
