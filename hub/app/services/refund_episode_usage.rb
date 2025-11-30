class RefundEpisodeUsage
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return unless user&.free?

    # current_for scopes to the current month. If the episode was created in a
    # previous month and fails now, no usage record exists for this month.
    # In that case, we skip the refund - the user loses that slot from the old month.
    usage = EpisodeUsage.current_for(user)
    return unless usage.persisted?

    usage.decrement!
  end

  private

  attr_reader :user
end
