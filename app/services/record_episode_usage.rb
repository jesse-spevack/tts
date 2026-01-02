class RecordEpisodeUsage
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return unless user.free?

    usage = EpisodeUsage.current_for(user)
    usage.increment!

    if usage.episode_count == AppConfig::Tiers::FREE_MONTHLY_EPISODES
      SendsUpgradeNudge.call(user: user)
    end
  end

  private

  attr_reader :user
end
