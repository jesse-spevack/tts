# frozen_string_literal: true

class ChecksEpisodeCreationPermission
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Result.success if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = AppConfig::Tiers::FREE_MONTHLY_EPISODES - usage.episode_count

    if remaining > 0
      Result.success(nil, remaining: remaining)
    elsif user.has_credits?
      Result.success(nil, using_credit: true)
    else
      Result.failure("Episode limit reached")
    end
  end

  private

  attr_reader :user

  def skip_tracking?
    !user.free?
  end
end
