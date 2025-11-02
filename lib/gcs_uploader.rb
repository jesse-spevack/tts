require "google/cloud/storage"

class GCSUploader
  class MissingBucketError < StandardError; end
  class MissingCredentialsError < StandardError; end
  class UploadError < StandardError; end

  attr_reader :bucket_name, :podcast_id

  # Initialize GCS uploader with bucket name and optional podcast_id
  # @param bucket_name [String] Name of the GCS bucket
  # @param podcast_id [String, nil] Optional podcast ID for path scoping
  def initialize(bucket_name, podcast_id: nil)
    raise MissingBucketError, "Bucket name cannot be nil or empty" if bucket_name.nil? || bucket_name.empty?

    @bucket_name = bucket_name
    @podcast_id = podcast_id
    @storage = nil
  end

  # Generate scoped path with podcast_id prefix if present
  # @param path [String] Original path
  # @return [String] Scoped path
  def scoped_path(path)
    return path unless @podcast_id

    "podcasts/#{@podcast_id}/#{path}"
  end

  # Upload a file to Google Cloud Storage and make it publicly accessible
  # @param local_path [String] Path to local file
  # @param remote_path [String] Destination path in GCS bucket (will be scoped if podcast_id present)
  # @return [String] Public URL of the uploaded file
  def upload_file(local_path:, remote_path:)
    raise UploadError, "Local file does not exist: #{local_path}" unless File.exist?(local_path)

    begin
      scoped_remote_path = scoped_path(remote_path)
      file = bucket.create_file(local_path, scoped_remote_path)
      file.acl.public!
      get_public_url(remote_path: remote_path)
    rescue Google::Cloud::Error => e
      raise UploadError, "Failed to upload file: #{e.message}"
    end
  end

  # Upload content directly to GCS (for JSON, XML, etc.)
  # @param content [String] Content to upload
  # @param remote_path [String] Destination path in GCS bucket (will be scoped if podcast_id present)
  # @return [String] Public URL of the uploaded content
  def upload_content(content:, remote_path:)
    scoped_remote_path = scoped_path(remote_path)

    # Upload the file
    file = bucket.create_file(StringIO.new(content), scoped_remote_path)
    file.acl.public!

    # Set cache control for RSS feeds to prevent stale content
    file.cache_control = "no-cache, max-age=0" if remote_path == "feed.xml"

    get_public_url(remote_path: remote_path)
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to upload content: #{e.message}"
  end

  # Download file content from GCS
  # @param remote_path [String] Path to file in GCS bucket (will be scoped if podcast_id present)
  # @return [String] File content as string with UTF-8 encoding
  def download_file(remote_path:)
    scoped_remote_path = scoped_path(remote_path)
    file = bucket.file(scoped_remote_path)
    raise UploadError, "File not found: #{scoped_remote_path}" unless file

    # Force UTF-8 encoding to prevent ASCII-8BIT encoding issues
    file.download.read.force_encoding("UTF-8")
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to download file: #{e.message}"
  end

  # Delete a file from GCS
  # @param remote_path [String] Path to file in GCS bucket (will be scoped if podcast_id present)
  # @return [Boolean] True if deleted, false if file didn't exist
  def delete_file(remote_path:)
    scoped_remote_path = scoped_path(remote_path)
    file = bucket.file(scoped_remote_path)
    return false unless file

    file.delete
    true
  rescue Google::Cloud::Error => e
    raise UploadError, "Failed to delete file: #{e.message}"
  end

  # Get public URL for a file in the bucket
  # @param remote_path [String] Path to file in GCS bucket (will be scoped if podcast_id present)
  # @return [String] Public HTTPS URL
  def get_public_url(remote_path:)
    scoped_remote_path = scoped_path(remote_path)
    # Remove leading slash if present
    path = scoped_remote_path.start_with?("/") ? scoped_remote_path[1..] : scoped_remote_path
    "https://storage.googleapis.com/#{bucket_name}/#{path}"
  end

  private

  # Lazy-load storage client
  def storage
    @storage ||= begin
      # On Cloud Run, credentials are automatic via service account
      # Only check for GOOGLE_APPLICATION_CREDENTIALS in local/test environments
      if !ENV["GOOGLE_APPLICATION_CREDENTIALS"] && ENV["RACK_ENV"] != "production"
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
