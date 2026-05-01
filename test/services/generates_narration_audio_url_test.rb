require "test_helper"
require "google/cloud/storage"

class GeneratesNarrationAudioUrlTest < ActiveSupport::TestCase
  setup do
    Mocktail.replace(Google::Cloud::Storage)
    ENV["SERVICE_ACCOUNT_EMAIL"] = "test@example.iam.gserviceaccount.com"
  end

  teardown do
    ENV.delete("SERVICE_ACCOUNT_EMAIL")
  end

  test "returns nil for incomplete narration" do
    narration = narrations(:one) # pending status
    assert_nil GeneratesNarrationAudioUrl.call(narration)
  end

  test "returns nil for narration without gcs_episode_id" do
    narration = narrations(:completed)
    narration.gcs_episode_id = nil
    assert_nil GeneratesNarrationAudioUrl.call(narration)
  end

  test "generates signed URL for complete narration" do
    narration = narrations(:completed)
    signed_url = "https://storage.googleapis.com/test-bucket/narrations/abc.mp3?X-Goog-Signature=deadbeef"

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) { |**_| signed_url }

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    result = GeneratesNarrationAudioUrl.call(narration)

    assert_equal signed_url, result
    assert_match(/X-Goog-Signature=/, result)
  end

  test "looks up GCS object at narrations/<gcs_episode_id>.mp3" do
    narration = narrations(:completed)
    captured_path = nil

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) { |**_| "https://example.com/signed" }

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) do |path|
      captured_path = path
      mock_file
    end

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    GeneratesNarrationAudioUrl.call(narration)

    assert_equal "narrations/#{narration.gcs_episode_id}.mp3", captured_path
  end

  test "uses IAM signer with service account email" do
    narration = narrations(:completed)
    captured_issuer = nil
    captured_signer = nil
    captured_expires = nil

    mock_file = Object.new
    mock_file.define_singleton_method(:signed_url) do |issuer:, signer:, expires:, **_|
      captured_issuer = issuer
      captured_signer = signer
      captured_expires = expires
      "https://example.com/signed"
    end

    mock_bucket = Object.new
    mock_bucket.define_singleton_method(:file) { |_| mock_file }

    mock_storage = Object.new
    mock_storage.define_singleton_method(:bucket) { |_| mock_bucket }

    stubs { |m| Google::Cloud::Storage.new(project_id: m.any) }.with { mock_storage }

    GeneratesNarrationAudioUrl.call(narration)

    assert_equal "test@example.iam.gserviceaccount.com", captured_issuer
    assert captured_signer.respond_to?(:call)
    assert_equal AppConfig::Storage::SIGNED_URL_EXPIRY_SECONDS, captured_expires
  end

  test "uses parameterized title for content-disposition filename" do
    narration = narrations(:completed)
    narration.title = "My Great Narration!"
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

    GeneratesNarrationAudioUrl.call(narration)

    assert_equal 'attachment; filename="my-great-narration.mp3"',
                 captured_query["response-content-disposition"]
  end

  test "falls back to gcs_episode_id when title is blank" do
    narration = narrations(:completed)
    # `title` has presence validation, so use save(validate: false) to simulate
    # a defensive fallback path — the service must never raise on a blank title.
    narration.title = ""
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

    GeneratesNarrationAudioUrl.call(narration)

    expected = "attachment; filename=\"#{narration.gcs_episode_id.parameterize}.mp3\""
    assert_equal expected, captured_query["response-content-disposition"]
  end
end
