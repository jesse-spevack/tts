# frozen_string_literal: true

class ProcessPasteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    Rails.logger.info "event=process_paste_episode_job_started episode_id=#{episode_id}"

    episode = Episode.find(episode_id)
    ProcessPasteEpisode.call(episode: episode)

    Rails.logger.info "event=process_paste_episode_job_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=process_paste_episode_job_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
