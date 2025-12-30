require "test_helper"
require "google/cloud/storage"

class GenerateEpisodeDownloadUrlTest < ActiveSupport::TestCase
  setup do
    Mocktail.replace(Google::Cloud::Storage)
    # Create a fake credentials file so we take the simple signing path
    @fake_credentials_file = Tempfile.new("fake_credentials")
    @fake_credentials_file.write("{}")
    @fake_credentials_file.close
    @original_credentials = ENV["GOOGLE_APPLICATION_CREDENTIALS"]
    ENV["GOOGLE_APPLICATION_CREDENTIALS"] = @fake_credentials_file.path
  end

  teardown do
    ENV["GOOGLE_APPLICATION_CREDENTIALS"] = @original_credentials
    @fake_credentials_file&.unlink
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

  test "generates signed URL for complete episode with gcs_episode_id" do
    episode = episodes(:two) # complete status
    signed_url = "https://storage.googleapis.com/test-bucket/test.mp3?signature=abc"

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) { |**_| signed_url }

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    result = GenerateEpisodeDownloadUrl.call(episode)
    assert_equal signed_url, result
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

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    GenerateEpisodeDownloadUrl.call(episode)

    assert_equal 'attachment; filename="my-great-episode.mp3"',
                 captured_query["response-content-disposition"]
  end

  test "uses IAM signer when no credentials file is present" do
    # Remove the fake credentials file to simulate production environment
    @fake_credentials_file.unlink
    ENV["GOOGLE_APPLICATION_CREDENTIALS"] = "/nonexistent/path"
    ENV["SERVICE_ACCOUNT_EMAIL"] = "test@example.iam.gserviceaccount.com"

    episode = episodes(:two)
    captured_issuer = nil
    captured_signer = nil

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) do |method:, expires:, query:, issuer:, signer:|
      captured_issuer = issuer
      captured_signer = signer
      "https://example.com/signed-with-iam"
    end

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    result = GenerateEpisodeDownloadUrl.call(episode)

    assert_equal "https://example.com/signed-with-iam", result
    assert_equal "test@example.iam.gserviceaccount.com", captured_issuer
    assert captured_signer.respond_to?(:call), "Expected signer to be a callable"
  ensure
    ENV.delete("SERVICE_ACCOUNT_EMAIL")
  end
end
