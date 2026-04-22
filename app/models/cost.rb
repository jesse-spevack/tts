# frozen_string_literal: true

# Immutable value representing the credit cost of an episode.
#
# Three states exist:
#   Cost.credits(2) — known cost (non-negative integer credits)
#   Cost.deferred   — cost not yet knowable (URL source; resolved after
#                     FetchesArticleContent in ProcessesUrlEpisode)
#   Cost.none       — no debit applies (free tier, complimentary, unlimited)
#
# Replaces the Integer | nil primitive that CalculatesAnticipatedEpisodeCost
# used to return. Eliminates nil-handling at every caller and makes the
# deferred contract explicit in the type system.
class Cost
  def self.credits(amount)
    new(:credits, amount)
  end

  def self.deferred
    new(:deferred, nil)
  end

  def self.none
    new(:none, 0)
  end

  attr_reader :kind, :credits

  def initialize(kind, credits)
    @kind = kind
    @credits = credits
    freeze
  end

  def deferred?
    kind == :deferred
  end

  # Deferred and none always satisfy a balance check:
  # - deferred: we don't know yet, let the async path decide at debit time.
  # - none: no debit is ever attempted, so any balance is sufficient.
  # For known credits, requires balance >= credits.
  def sufficient_for?(balance)
    return true if deferred? || kind == :none

    balance >= credits
  end

  def ==(other)
    other.is_a?(Cost) && other.kind == kind && other.credits == credits
  end
  alias_method :eql?, :==

  def hash
    [ self.class, kind, credits ].hash
  end
end
