# frozen_string_literal: true

class GeneratesEpisodeAudioJob < ApplicationJob
  include EpisodeJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, **) { Episode.find(episode_id).user_id }

  retry_on *TransientAudioErrors::TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.handle_retries_exhausted(error)
  end

  def perform(episode_id:, action_id: nil, voice_override: nil)
    with_episode_logging(episode_id: episode_id, user_id: nil, action_id: action_id) do
      episode = Episode.find(episode_id)
      ChecksAudioCircuitBreaker.call(user: episode.user) do
        GeneratesEpisodeAudio.call(episode: episode, voice_override: voice_override)
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
