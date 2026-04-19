# frozen_string_literal: true

module EpisodeJobLogging
  extend ActiveSupport::Concern

  private

  def with_episode_logging(episode_id:, user_id:, action_id: nil)
    @episode_skipped = false
    Current.action_id = action_id
    log_event("started", episode_id: episode_id, user_id: user_id)
    yield
    log_event("completed", episode_id: episode_id) unless @episode_skipped
  rescue StandardError => e
    log_event("failed", episode_id: episode_id, error: e.class, message: e.message, exception: e)
    raise
  end

  # Guard for a missing/soft-deleted owner. episode.user is nil when the user's
  # default_scope hides them (deleted_at set) or they were hard-deleted. Without
  # this the job 500s with NoMethodError deep in the pipeline. Mark the episode
  # failed so the UI shows an error card and the episode exits the processing
  # state — otherwise it gets stuck on the user's restored account.
  def skip_if_user_missing(episode)
    return false unless episode.user.nil?

    episode.update!(status: :failed, error_message: "Account was deleted")
    @episode_skipped = true
    log_event("skipped", episode_id: episode.id, reason: "user_missing_or_soft_deleted")
    true
  end

  def log_event(status, **attrs)
    exception = attrs.delete(:exception)
    event_name = "#{job_type}_#{status}"
    attrs_with_action = { action_id: Current.action_id }.merge(attrs)
    log_parts = attrs_with_action.compact.map { |k, v| "#{k}=#{v}" }.join(" ")
    message = "event=#{event_name} #{log_parts}"

    if exception.respond_to?(:backtrace) && exception.backtrace
      message = "#{message}\n#{exception.class}: #{exception.message}\n#{exception.backtrace.join("\n")}"
    end

    Rails.logger.public_send(log_level_for(status), message)
  end

  def log_level_for(status)
    case status
    when "failed" then :error
    when "skipped" then :warn
    else :info
    end
  end

  def job_type
    self.class.name.underscore
  end
end
