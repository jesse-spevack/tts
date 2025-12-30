require "test_helper"
require "google/cloud/storage"

class GenerateEpisodeDownloadUrlTest < ActiveSupport::TestCase
  setup do
    Mocktail.replace(Google::Cloud::Storage)
    ENV["SERVICE_ACCOUNT_EMAIL"] = "test@example.iam.gserviceaccount.com"
  end

  teardown do
    ENV.delete("SERVICE_ACCOUNT_EMAIL")
  end

  test "returns nil for incomplete episode" do
    episode = episodes(:one) # pending status
    assert_nil GenerateEpisodeDownloadUrl.call(episode)
  end

  test "returns nil for episode without gcs_episode_id" do
    episode = episodes(:two)
    episode.gcs_episode_id = nil
    assert_nil GenerateEpisodeDownloadUrl.call(episode)
  end

  test "generates signed URL for complete episode" do
    episode = episodes(:two)
    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) { |**_| signed_url }

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    assert_equal signed_url, GenerateEpisodeDownloadUrl.call(episode)
  end

  test "uses IAM signer with service account email" do
    episode = episodes(:two)
    captured_issuer = nil
    captured_signer = nil

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) do |issuer:, signer:, **_|
      captured_issuer = issuer
      captured_signer = signer
      "https://example.com/signed"
    end

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    GenerateEpisodeDownloadUrl.call(episode)

    assert_equal "test@example.iam.gserviceaccount.com", captured_issuer
    assert captured_signer.respond_to?(:call)
  end

  test "uses parameterized title for filename" do
    episode = episodes(:two)
    episode.title = "My Great Episode!"
    captured_query = nil

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) do |query:, **_|
      captured_query = query
      "https://example.com/signed"
    end

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    GenerateEpisodeDownloadUrl.call(episode)

    assert_equal 'attachment; filename="my-great-episode.mp3"',
                 captured_query["response-content-disposition"]
  end
end
