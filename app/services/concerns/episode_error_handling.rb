# frozen_string_literal: true

module EpisodeErrorHandling
  extend ActiveSupport::Concern

  class ProcessingError < StandardError; end

  included do
    include EpisodeLogging
  end

  private

  # Marks the episode failed and refunds any credit debit made earlier in
  # the processing lifecycle. Credit users debit at CreatesEpisode (paste/
  # email/file) or at ProcessesUrlEpisode#deduct_credit (url); without this
  # refund, a failure after debit leaves the user short a credit — see
  # agent-team-uoqd. Keeping the refund in the shared concern covers all
  # four Processes*Episode services at one site.
  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    RefundsCreditDebit.call(episode: episode)
    log_warn "episode_marked_failed", error: error_message
  end
end
