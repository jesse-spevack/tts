class CanClaimFreeEpisode
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return true unless user.free?

    !FreeEpisodeClaim.active.exists?(user: user)
  end

  private

  attr_reader :user
end
