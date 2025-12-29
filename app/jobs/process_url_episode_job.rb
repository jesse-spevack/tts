class ProcessUrlEpisodeJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, user_id:) { user_id }

  def perform(episode_id:, user_id:)
    Rails.logger.info "event=process_url_episode_job_started episode_id=#{episode_id} user_id=#{user_id}"

    episode = Episode.find(episode_id)
    ProcessUrlEpisode.call(episode: episode)

    Rails.logger.info "event=process_url_episode_job_completed episode_id=#{episode_id}"
  rescue StandardError => e
    Rails.logger.error "event=process_url_episode_job_failed episode_id=#{episode_id} error=#{e.class} message=#{e.message}"
    raise
  end
end
