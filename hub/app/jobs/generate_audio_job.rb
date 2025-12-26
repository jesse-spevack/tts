# frozen_string_literal: true

class GenerateAudioJob < ApplicationJob
  queue_as :default

  def perform(episode)
    Rails.logger.info "event=generate_audio_job_started episode_id=#{episode.id}"
    GenerateEpisodeAudio.call(episode: episode)
    Rails.logger.info "event=generate_audio_job_completed episode_id=#{episode.id}"
  end
end
