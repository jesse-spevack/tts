# frozen_string_literal: true

class ProcessMarkdownEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    Rails.logger.info "event=process_markdown_episode_job_started episode_id=#{episode_id}"

    episode = Episode.find(episode_id)
    ProcessMarkdownEpisode.call(episode: episode)

    Rails.logger.info "event=process_markdown_episode_job_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=process_markdown_episode_job_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
