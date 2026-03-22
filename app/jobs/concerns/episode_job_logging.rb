# frozen_string_literal: true

module EpisodeJobLogging
  extend ActiveSupport::Concern

  private

  def with_episode_logging(episode_id:, user_id:, action_id: nil)
    Current.action_id = action_id
    log_event("started", episode_id: episode_id, user_id: user_id)
    yield
    log_event("completed", episode_id: episode_id)
  rescue StandardError => e
    log_event("failed", episode_id: episode_id, error: e.class, message: e.message, exception: e)
    raise
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

    log_method = status == "failed" ? :error : :info
    Rails.logger.public_send(log_method, message)
  end

  def job_type
    self.class.name.underscore
  end
end
