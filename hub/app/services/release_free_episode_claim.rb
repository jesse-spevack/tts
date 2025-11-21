class ReleaseFreeEpisodeClaim
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    claim = FreeEpisodeClaim.active.find_by(episode: episode)
    return nil unless claim

    claim.update!(released_at: Time.current)
    claim
  end

  private

  attr_reader :episode
end
