# frozen_string_literal: true

module EpisodeErrorHandling
  extend ActiveSupport::Concern

  class ProcessingError < StandardError; end

  included do
    include EpisodeLogging
  end

  private

  # Marks the episode failed and refunds via the unified RefundsPayment
  # orchestrator. RefundsPayment dispatches to the right path (MPP / credit /
  # free-tier) based on what the content has. Keeping the refund in the
  # shared concern covers all four Processes*Episode services at one site.
  #
  # The `saved_change_to_status?` gate prevents double-decrementing the
  # free-tier EpisodeUsage counter when the episode was already marked
  # :failed by another path. Credit and MPP refunds have their own
  # idempotency (stripe_session_id unique constraint and MppPayment status
  # check respectively), but EpisodeUsage#decrement! has no episode-identity
  # idempotency — the gate is the only thing protecting that counter.
  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    RefundsPayment.call(content: episode) if episode.saved_change_to_status?
    log_warn "episode_marked_failed", error: error_message
  end
end
