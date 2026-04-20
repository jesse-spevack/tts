# frozen_string_literal: true

# Encapsulates the "should we debit, and if so for how much?" decision for the
# sync episode-creation paths (web, API v1, MCP text tool). Previously the
# three callers each hand-rolled the same guard chain:
#
#   return if user.complimentary? || user.unlimited?
#   return if episode.url?
#   DeductsCredit.call(user:, episode:, cost_in_credits:)
#
# The bypass rules live here:
#
# * Complimentary / Unlimited account types never pay credits (internal ops).
# * URL episodes defer the debit to ProcessesUrlEpisode — the real character
#   count isn't known until fetch+extract, so sync pricing is wrong.
# * Everyone else delegates to DeductsCredit at the anticipated cost.
#
# Return shape (via Result) lets callers distinguish three outcomes:
#
#   Result.success(status: :skipped, reason: :complimentary | :unlimited | :url_deferred)
#   Result.success(status: :debited,  balance: <CreditBalance>)
#   Result.failure(...)  # propagated straight from DeductsCredit
#
# URL debits in the async job still call DeductsCredit directly — this service
# is only for the synchronous submission paths.
class DebitsEpisodeCredit
  def self.call(user:, episode:, cost_in_credits:)
    new(user: user, episode: episode, cost_in_credits: cost_in_credits).call
  end

  def initialize(user:, episode:, cost_in_credits:)
    @user = user
    @episode = episode
    @cost_in_credits = cost_in_credits
  end

  def call
    return Result.success(status: :skipped, reason: :complimentary) if user.complimentary?
    return Result.success(status: :skipped, reason: :unlimited)     if user.unlimited?
    return Result.success(status: :skipped, reason: :url_deferred)  if episode.url?

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: cost_in_credits)
    return result if result.failure?

    Result.success(status: :debited, balance: result.data)
  end

  private

  attr_reader :user, :episode, :cost_in_credits
end
