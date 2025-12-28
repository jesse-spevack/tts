class ChecksEpisodeCreationPermission
  FREE_MONTHLY_LIMIT = 2

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Outcome.success if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = FREE_MONTHLY_LIMIT - usage.episode_count

    if remaining > 0
      Outcome.success(nil, remaining: remaining)
    else
      Outcome.failure("Episode limit reached")
    end
  end

  private

  attr_reader :user

  def skip_tracking?
    !user.free?
  end
end
