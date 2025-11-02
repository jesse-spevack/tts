require "minitest/autorun"
require_relative "../lib/episode_processor"

class TestEpisodeProcessor < Minitest::Test
  def test_initializes_with_bucket_name_and_podcast_id
    processor = EpisodeProcessor.new("test-bucket", "podcast_123")
    assert_instance_of EpisodeProcessor, processor
    assert_equal "test-bucket", processor.bucket_name
    assert_equal "podcast_123", processor.podcast_id
  end

  def test_raises_error_without_podcast_id
    error = assert_raises(ArgumentError) do
      EpisodeProcessor.new("test-bucket", nil)
    end
    assert_match(/podcast_id is required/, error.message)
  end
end
