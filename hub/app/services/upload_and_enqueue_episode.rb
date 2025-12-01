# frozen_string_literal: true

class UploadAndEnqueueEpisode
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    staging_path = upload_to_staging

    Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

    enqueue_processing(staging_path)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  private

  attr_reader :episode, :content

  def upload_to_staging
    filename = "#{episode.id}-#{Time.now.to_i}.md"

    gcs_uploader.upload_staging_file(content: content, filename: filename)
  end

  def enqueue_processing(staging_path)
    tasks_enqueuer.enqueue_episode_processing(
      episode_id: episode.id,
      podcast_id: episode.podcast.podcast_id,
      staging_path: staging_path,
      metadata: {
        title: episode.title,
        author: episode.author,
        description: episode.description
      },
      voice_name: episode.user.voice_name
    )
  end

  def gcs_uploader
    @gcs_uploader ||= GcsUploader.new(
      ENV.fetch("GOOGLE_CLOUD_BUCKET"),
      podcast_id: episode.podcast.podcast_id
    )
  end

  def tasks_enqueuer
    @tasks_enqueuer ||= CloudTasksEnqueuer.new
  end
end
