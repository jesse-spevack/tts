# frozen_string_literal: true

class GeneratesEpisodeAudioJob < ApplicationJob
  include EpisodeJobLogging

  class CircuitBreakerTrippedError < StandardError; end

  CIRCUIT_BREAKER_THRESHOLD = 3
  CIRCUIT_BREAKER_WINDOW = 1.hour

  queue_as :default
  limits_concurrency to: 1, key: ->(episode_id:, **) { Episode.find(episode_id).user_id }

  retry_on *TransientAudioErrors::TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.handle_retries_exhausted(error)
  end

  def perform(episode_id:, action_id: nil)
    with_episode_logging(episode_id: episode_id, user_id: nil, action_id: action_id) do
      episode = Episode.find(episode_id)
      check_circuit_breaker!(episode.user)
      GeneratesEpisodeAudio.call(episode: episode)
      reset_circuit_breaker(episode.user)
    end
  rescue CircuitBreakerTrippedError => e
    Episode.find_by(id: episode_id)&.update!(status: :failed, error_message: e.message)
  end

  def handle_retries_exhausted(error)
    episode = find_episode
    return unless episode

    increment_circuit_breaker(episode.user)
    episode.update!(status: :failed, error_message: "Audio generation failed after retries: #{error.message}")
  end

  private

  def find_episode
    args = (arguments.first || {}).with_indifferent_access
    Episode.find_by(id: args[:episode_id])
  end

  def check_circuit_breaker!(user)
    count = Rails.cache.read(circuit_breaker_key(user)) || 0
    return if count < CIRCUIT_BREAKER_THRESHOLD

    Rails.logger.warn("Audio circuit breaker tripped for user #{user.id} (#{count} failures in the last hour)")
    raise CircuitBreakerTrippedError, "Audio service temporarily unavailable, please retry later"
  end

  def increment_circuit_breaker(user)
    key = circuit_breaker_key(user)
    count = Rails.cache.read(key) || 0
    Rails.cache.write(key, count + 1, expires_in: CIRCUIT_BREAKER_WINDOW)
  end

  def reset_circuit_breaker(user)
    Rails.cache.delete(circuit_breaker_key(user))
  end

  def circuit_breaker_key(user)
    "audio_failures:#{user.id}"
  end
end
