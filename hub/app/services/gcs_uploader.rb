require "google/cloud/storage"

class GcsUploader
  def initialize(bucket_name, podcast_id:)
    @bucket_name = bucket_name
    @podcast_id = podcast_id
    @storage = Google::Cloud::Storage.new
  end

  def upload_staging_file(content:, filename:)
    path = "podcasts/#{@podcast_id}/staging/#{filename}"
    bucket.create_file(StringIO.new(content), path)
    path
  end

  private

  def bucket
    @bucket ||= @storage.bucket(@bucket_name)
  end
end
