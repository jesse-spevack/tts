require "google/cloud/storage"
require "base64"
require "json"

class GcsUploader
  def initialize(bucket_name, podcast_id:)
    @bucket_name = bucket_name
    @podcast_id = podcast_id
    @storage = build_storage_client
  end

  def upload_staging_file(content:, filename:)
    path = "podcasts/#{@podcast_id}/staging/#{filename}"
    bucket.create_file(StringIO.new(content), path)
    path
  end

  private

  def build_storage_client
    if ENV["KAMAL_REGISTRY_PASSWORD"].present?
      credentials = decode_credentials
      Google::Cloud::Storage.new(credentials: credentials)
    else
      Google::Cloud::Storage.new
    end
  end

  def decode_credentials
    decoded = Base64.decode64(ENV["KAMAL_REGISTRY_PASSWORD"])
    JSON.parse(decoded)
  rescue ArgumentError => e
    raise "Failed to decode KAMAL_REGISTRY_PASSWORD as base64: #{e.message}"
  rescue JSON::ParserError => e
    raise "Failed to parse KAMAL_REGISTRY_PASSWORD as JSON: #{e.message}"
  end

  def bucket
    @bucket ||= @storage.bucket(@bucket_name)
  end
end
