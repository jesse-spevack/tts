require "test_helper"
require "minitest/mock"
require "google/cloud/storage"

class GenerateEpisodeDownloadUrlTest < ActiveSupport::TestCase
  test "returns nil for incomplete episode" do
    episode = episodes(:one) # pending status
    assert_nil GenerateEpisodeDownloadUrl.call(episode)
  end

  test "returns nil for episode without gcs_episode_id" do
    episode = episodes(:two)
    episode.gcs_episode_id = nil
    assert_nil GenerateEpisodeDownloadUrl.call(episode)
  end

  test "generates signed URL for complete episode with gcs_episode_id" do
    episode = episodes(:two) # complete status
    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) { |**_| signed_url }

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    GoogleCredentials.stub :from_env, {} do
      Google::Cloud::Storage.stub :new, mock_storage do
        result = GenerateEpisodeDownloadUrl.call(episode)
        assert_equal signed_url, result
      end
    end
  end

  test "uses parameterized title for filename" do
    episode = episodes(:two)
    episode.title = "My Great Episode!"

    captured_query = nil

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) do |method:, expires:, query:|
      captured_query = query
      "https://example.com/signed"
    end

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    GoogleCredentials.stub :from_env, {} do
      Google::Cloud::Storage.stub :new, mock_storage do
        GenerateEpisodeDownloadUrl.call(episode)
      end
    end

    assert_equal 'attachment; filename="my-great-episode.mp3"',
                 captured_query["response-content-disposition"]
  end
end
