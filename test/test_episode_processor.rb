require "minitest/autorun"
require_relative "../lib/episode_processor"

class TestEpisodeProcessor < Minitest::Test
  def setup
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
  end

  def test_initialization_with_explicit_bucket
    processor = EpisodeProcessor.new("my-bucket")
    assert_equal "my-bucket", processor.bucket_name
  end

  def test_initialization_uses_env_bucket
    processor = EpisodeProcessor.new
    assert_equal "test-bucket", processor.bucket_name
  end
end
