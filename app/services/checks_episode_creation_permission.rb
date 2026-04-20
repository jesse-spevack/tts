# frozen_string_literal: true

class ChecksEpisodeCreationPermission
  def self.call(user:, anticipated_cost: nil)
    new(user: user, anticipated_cost: anticipated_cost).call
  end

  def initialize(user:, anticipated_cost:)
    @user = user
    @anticipated_cost = anticipated_cost
  end

  def call
    return Result.success if user.complimentary? || user.unlimited?

    if user.free?
      check_free_quota
    else
      check_credit_balance
    end
  end

  private

  attr_reader :user, :anticipated_cost

  def check_free_quota
    usage = EpisodeUsage.current_for(user)
    remaining = AppConfig::Tiers::FREE_MONTHLY_EPISODES - usage.episode_count

    if remaining > 0
      Result.success(nil, remaining: remaining)
    else
      Result.failure("Episode limit reached", code: :episode_limit_reached)
    end
  end

  # anticipated_cost is optional. When nil, callers (typically the web /new
  # page gate) skip the credit-balance check — they only want to know
  # whether the user could ever create an episode. The actual /create
  # endpoints always pass a cost so the balance gate fires before any
  # episode or CreditTransaction is written.
  def check_credit_balance
    return Result.success if anticipated_cost.nil?
    return Result.success if user.credits_remaining >= anticipated_cost

    Result.failure("Insufficient credits", code: :insufficient_credits)
  end
end
