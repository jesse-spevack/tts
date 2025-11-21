class ClaimFreeEpisode
  def self.call(user:, episode:)
    new(user: user, episode: episode).call
  end

  def initialize(user:, episode:)
    @user = user
    @episode = episode
  end

  def call
    return nil unless user.free?

    FreeEpisodeClaim.create!(
      user: user,
      episode: episode,
      claimed_at: Time.current
    )
  end

  private

  attr_reader :user, :episode
end
