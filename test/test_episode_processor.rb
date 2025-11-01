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

  def test_generate_filename_includes_date_and_slug
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "Test Episode Title")

    assert_match(/^\d{4}-\d{2}-\d{2}-test-episode-title$/, filename)
  end

  def test_generate_filename_removes_special_chars
    processor = EpisodeProcessor.new
    filename = processor.send(:generate_filename, "Test (Special) Chars!")

    assert_match(/test-special-chars$/, filename)
  end
end
