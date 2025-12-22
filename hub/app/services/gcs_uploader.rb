require "google/cloud/storage"

class GcsUploader
  def initialize(bucket_name = nil, podcast_id:)
    @bucket_name = bucket_name || ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    @podcast_id = podcast_id
    @storage = build_storage_client
  end

  def upload_staging_file(content:, filename:)
    full_path = "podcasts/#{@podcast_id}/staging/#{filename}"
    bucket.create_file(StringIO.new(content), full_path)
    "staging/#{filename}"
  end

  def upload_content(content:, remote_path:)
    full_path = scoped_path(remote_path)
    file = bucket.create_file(StringIO.new(content), full_path)
    file.acl.public!
    file.cache_control = "no-cache, max-age=0" if remote_path == "feed.xml"
  end

  def download_file(remote_path:)
    full_path = scoped_path(remote_path)
    file = bucket.file(full_path)
    raise "File not found: #{full_path}" unless file

    file.download.read.force_encoding("UTF-8")
  end

  def delete_file(remote_path:)
    full_path = scoped_path(remote_path)
    file = bucket.file(full_path)
    return false unless file

    file.delete
    true
  end

  private

  def scoped_path(path)
    "podcasts/#{@podcast_id}/#{path}"
  end

  def build_storage_client
    Google::Cloud::Storage.new(credentials: GoogleCredentials.from_env)
  end

  def bucket
    @bucket ||= @storage.bucket(@bucket_name)
  end
end
