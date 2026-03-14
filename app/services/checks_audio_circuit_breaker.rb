# frozen_string_literal: true

class ChecksAudioCircuitBreaker
  class Tripped < StandardError; end

  THRESHOLD = 3
  WINDOW = 1.hour

  def self.check!(user)
    count = Rails.cache.read(cache_key(user)) || 0
    return if count < THRESHOLD

    Rails.logger.warn("Audio circuit breaker tripped for user #{user.id} (#{count} failures in the last hour)")
    raise Tripped, "Audio service temporarily unavailable, please retry later"
  end

  def self.increment(user)
    key = cache_key(user)
    count = Rails.cache.read(key) || 0
    Rails.cache.write(key, count + 1, expires_in: WINDOW)
  end

  def self.reset(user)
    Rails.cache.delete(cache_key(user))
  end

  def self.cache_key(user)
    "audio_failures:#{user.id}"
  end
  private_class_method :cache_key
end
