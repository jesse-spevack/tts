# frozen_string_literal: true

module EpisodeErrorHandling
  extend ActiveSupport::Concern

  class ProcessingError < StandardError; end

  included do
    include EpisodeLogging
  end

  private

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    log_warn "episode_marked_failed", error: error_message
  end
end
