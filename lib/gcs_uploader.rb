require "google/cloud/storage"

class GCSUploader
  class MissingBucketError < StandardError; end
  class MissingCredentialsError < StandardError; end
  class UploadError < StandardError; end

  attr_reader :bucket_name

  # Initialize GCS uploader with bucket name
  # @param bucket_name [String] Name of the GCS bucket
  def initialize(bucket_name)
    raise MissingBucketError, "Bucket name cannot be nil or empty" if bucket_name.nil? || bucket_name.empty?

    @bucket_name = bucket_name
    @storage = nil
  end

  # Upload a file to Google Cloud Storage and make it publicly accessible
  # @param local_path [String] Path to local file
  # @param remote_path [String] Destination path in GCS bucket
  # @return [String] Public URL of the uploaded file
  def upload_file(local_path:, remote_path:)
    raise UploadError, "Local file does not exist: #{local_path}" unless File.exist?(local_path)

    begin
      file = bucket.create_file(local_path, remote_path)
      file.acl.public!
      get_public_url(remote_path: remote_path)
    rescue Google::Cloud::Error => e
      raise UploadError, "Failed to upload file: #{e.message}"
    end
  end

  # Upload content directly to GCS (for JSON, XML, etc.)
  # @param content [String] Content to upload
  # @param remote_path [String] Destination path in GCS bucket
  # @return [String] Public URL of the uploaded content
  def upload_content(content:, remote_path:)
    file = bucket.create_file(StringIO.new(content), remote_path)
    file.acl.public!
    get_public_url(remote_path: remote_path)
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to upload content: #{e.message}"
  end

  # Download file content from GCS
  # @param remote_path [String] Path to file in GCS bucket
  # @return [String] File content as string
  def download_file(remote_path:)
    file = bucket.file(remote_path)
    raise UploadError, "File not found: #{remote_path}" unless file

    file.download.read
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to download file: #{e.message}"
  end

  # Get public URL for a file in the bucket
  # @param remote_path [String] Path to file in GCS bucket
  # @return [String] Public HTTPS URL
  def get_public_url(remote_path:)
    # Remove leading slash if present
    path = remote_path.start_with?("/") ? remote_path[1..] : remote_path
    "https://storage.googleapis.com/#{bucket_name}/#{path}"
  end

  private

  # Lazy-load storage client
  def storage
    @storage ||= begin
      unless ENV["GOOGLE_APPLICATION_CREDENTIALS"]
        raise MissingCredentialsError,
              "GOOGLE_APPLICATION_CREDENTIALS not set"
      end

      Google::Cloud::Storage.new
    rescue Google::Cloud::Error => e
      raise MissingCredentialsError, "Failed to initialize Google Cloud Storage: #{e.message}"
    end
  end

  # Get bucket object
  def bucket
    @bucket ||= begin
      b = storage.bucket(bucket_name)
      raise UploadError, "Bucket '#{bucket_name}' not found" unless b

      b
    end
  end
end
