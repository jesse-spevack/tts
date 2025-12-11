# frozen_string_literal: true

class UploadEpisodeContent
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    filename = "#{episode.id}-#{Time.now.to_i}.txt"
    gcs_uploader.upload_staging_file(content: content, filename: filename)
  end

  private

  attr_reader :episode, :content

  def gcs_uploader
    @gcs_uploader ||= GcsUploader.new(
      ENV.fetch("GOOGLE_CLOUD_BUCKET"),
      podcast_id: episode.podcast.podcast_id
    )
  end
end
