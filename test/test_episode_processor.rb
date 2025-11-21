require "minitest/autorun"
require_relative "../lib/episode_processor"

class TestEpisodeProcessor < Minitest::Test
  def test_initializes_with_valid_podcast_id
    processor = EpisodeProcessor.new("test-bucket", "podcast_a1b2c3d4e5f6a7b8")
    assert_instance_of EpisodeProcessor, processor
    assert_equal "test-bucket", processor.bucket_name
    assert_equal "podcast_a1b2c3d4e5f6a7b8", processor.podcast_id
  end

  def test_raises_error_without_podcast_id
    error = assert_raises(ArgumentError) do
      EpisodeProcessor.new("test-bucket", nil)
    end
    assert_match(/podcast_id is required/, error.message)
  end

  def test_raises_error_with_invalid_podcast_id_format
    invalid_ids = [
      "podcast_123",                  # Too short
      "podcast_ABCD1234abcd5678",     # Has uppercase
      "podcast_xyz123abc456def78",    # Has non-hex chars
      "podcast_a1b2c3d4e5f6a7b89",    # Too long (17 chars)
      "podcast_a1b2c3d4e5f6a7b",      # Too short (15 chars)
      "abc123def456abc123de",         # Missing prefix
      "PODCAST_a1b2c3d4e5f6a7b8"      # Wrong prefix case
    ]

    invalid_ids.each do |invalid_id|
      error = assert_raises(ArgumentError) do
        EpisodeProcessor.new("test-bucket", invalid_id)
      end
      assert_match(/Invalid podcast_id format/, error.message)
      assert_match(/openssl rand -hex 8/, error.message)
    end
  end

  def test_process_accepts_voice_name_parameter
    processor = EpisodeProcessor.new("test-bucket", "podcast_a1b2c3d4e5f6a7b8")

    with_process_stubs(tts_stub: mock_tts) do
      # Should not raise - voice_name is accepted
      processor.process(title: "Test", author: "Author", description: "Desc",
                        markdown_content: "# Test", voice_name: "en-GB-Standard-D")
    end
  end

  def test_process_configures_tts_with_voice_name
    processor = EpisodeProcessor.new("test-bucket", "podcast_a1b2c3d4e5f6a7b8")
    tts_config_received = nil

    tts_stub = lambda do |config:|
      tts_config_received = config
      mock_tts
    end

    with_process_stubs(tts_stub: tts_stub) do
      processor.process(title: "Test", author: "Author", description: "Desc",
                        markdown_content: "# Test", voice_name: "en-GB-Standard-D")
    end

    assert_equal "en-GB-Standard-D", tts_config_received.voice_name
  end

  private

  def mock_tts
    mock = Object.new
    mock.define_singleton_method(:synthesize) { |_text| "audio" }
    mock
  end

  def mock_publisher
    mock = Object.new
    mock.define_singleton_method(:publish) { |**_args| { "id" => "ep1" } }
    mock
  end

  def with_process_stubs(tts_stub:, &)
    TTS.stub :new, tts_stub do
      TextProcessor.stub :convert_to_plain_text, "text" do
        PodcastPublisher.stub :new, mock_publisher do
          YAML.stub :safe_load_file, {} do
            GCSUploader.stub(:new, Object.new) { EpisodeManifest.stub(:new, Object.new, &) }
          end
        end
      end
    end
  end
end
