class CanCreateEpisode
  FREE_MONTHLY_LIMIT = 2

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Result.allowed if skip_tracking?

    usage = EpisodeUsage.current_for(user)
    remaining = FREE_MONTHLY_LIMIT - usage.episode_count

    if remaining > 0
      Result.allowed(remaining: remaining)
    else
      Result.denied
    end
  end

  private

  attr_reader :user

  def skip_tracking?
    !user.free?
  end

  class Result
    attr_reader :remaining

    def self.allowed(remaining: nil)
      new(allowed: true, remaining: remaining)
    end

    def self.denied
      new(allowed: false, remaining: 0)
    end

    def initialize(allowed:, remaining:)
      @allowed = allowed
      @remaining = remaining
    end

    def allowed?
      @allowed
    end

    def denied?
      !@allowed
    end
  end
end
