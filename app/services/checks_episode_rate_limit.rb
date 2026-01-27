# frozen_string_literal: true

class ChecksEpisodeRateLimit
  include StructuredLogging

  HOURLY_LIMIT = 20

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    episodes_this_hour = user.episodes.where("created_at >= ?", 1.hour.ago).count

    if episodes_this_hour >= HOURLY_LIMIT
      log_warn "rate_limit_exceeded", user_id: user.id, count: episodes_this_hour
      Result.failure("You've reached your hourly episode limit")
    else
      Result.success(nil, remaining: HOURLY_LIMIT - episodes_this_hour)
    end
  end

  private

  attr_reader :user
end
