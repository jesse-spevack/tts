# frozen_string_literal: true

class GeneratesEpisodeAudioJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, **) { Episode.find(episode_id).user_id }

  retry_on *TransientAudioErrors::TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.handle_retries_exhausted(error)
  end

  def perform(episode_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: nil, action_id: action_id) do
      episode = Episode.find(episode_id)
      # episode.user is nil when the owner is soft-deleted (User.default_scope)
      # or hard-deleted. Guard explicitly so we log + bail rather than 500ing
      # with NoMethodError deep inside the audio pipeline.
      if episode.user.nil?
        Rails.logger.warn(
          "event=generate_episode_audio_skipped " \
          "episode_id=#{episode_id} " \
          "reason=user_missing_or_soft_deleted"
        )
        next
      end
      ChecksAudioCircuitBreaker.call(user: episode.user) do
        GeneratesEpisodeAudio.call(episode: episode)
      end
    end
  rescue ChecksAudioCircuitBreaker::Tripped => e
    Episode.find_by(id: episode_id)&.update!(status: :failed, error_message: e.message)
  end

  def handle_retries_exhausted(error)
    episode = find_episode
    return unless episode

    ChecksAudioCircuitBreaker.increment(episode.user)
    episode.update!(status: :failed, error_message: "Audio generation failed after retries: #{error.message}")
  end

  private

  def find_episode
    args = (arguments.first || {}).with_indifferent_access
    Episode.find_by(id: args[:episode_id])
  end
end
