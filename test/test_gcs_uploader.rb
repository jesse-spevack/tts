require "minitest/autorun"
require_relative "../lib/gcs_uploader"

class TestGCSUploader < Minitest::Test
  def test_initializes_with_bucket_name
    uploader = GCSUploader.new("test-bucket")
    assert_instance_of GCSUploader, uploader
  end

  def test_raises_error_when_bucket_name_nil
    assert_raises(GCSUploader::MissingBucketError) do
      GCSUploader.new(nil)
    end
  end

  def test_raises_error_when_bucket_name_empty
    assert_raises(GCSUploader::MissingBucketError) do
      GCSUploader.new("")
    end
  end

  def test_get_public_url_returns_correct_format
    uploader = GCSUploader.new("my-bucket")
    url = uploader.get_public_url(remote_path: "episodes/test.mp3")

    assert_equal "https://storage.googleapis.com/my-bucket/episodes/test.mp3", url
  end

  def test_get_public_url_handles_paths_without_leading_slash
    uploader = GCSUploader.new("my-bucket")
    url = uploader.get_public_url(remote_path: "feed.xml")

    assert_equal "https://storage.googleapis.com/my-bucket/feed.xml", url
  end

  def test_get_public_url_handles_paths_with_leading_slash
    uploader = GCSUploader.new("my-bucket")
    url = uploader.get_public_url(remote_path: "/episodes/test.mp3")

    assert_equal "https://storage.googleapis.com/my-bucket/episodes/test.mp3", url
  end
end
