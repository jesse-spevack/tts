# frozen_string_literal: true

class SubmitEpisodeForProcessing
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    staging_path = upload_content(wrap_content)

    Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

    enqueue_processing(staging_path)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  private

  attr_reader :episode, :content

  def wrap_content
    BuildEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      tier: episode.user.tier,
      content: content
    )
  end

  def upload_content(wrapped_content)
    UploadEpisodeContent.call(episode: episode, content: wrapped_content)
  end

  def enqueue_processing(staging_path)
    EnqueueEpisodeProcessing.call(episode: episode, staging_path: staging_path)
  end
end
