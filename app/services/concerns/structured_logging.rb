# frozen_string_literal: true

module StructuredLogging
  extend ActiveSupport::Concern

  # log_info/log_warn/log_error are the logging API callers use — public so
  # retry_on blocks (which yield a detached job instance) can invoke them
  # without `send`. The build_log_message / default_log_context helpers stay
  # private.

  def log_info(event, **attrs)
    Rails.logger.info build_log_message(event, attrs)
  end

  def log_warn(event, **attrs)
    Rails.logger.warn build_log_message(event, attrs)
  end

  # Pass exception: to include backtrace for Cloud Error Reporting
  def log_error(event, **attrs)
    Rails.logger.error build_log_message(event, attrs)
  end

  private

  def default_log_context
    { action_id: Current.action_id, api_token_prefix: Current.api_token_prefix }.compact
  end

  def build_log_message(event, attrs)
    exception = attrs.delete(:exception)
    context = default_log_context.merge(attrs)
    parts = [ "event=#{event}" ]
    context.each { |k, v| parts << "#{k}=#{v}" if v.present? }
    message = parts.join(" ")

    if exception.respond_to?(:backtrace) && exception.backtrace
      message = "#{message}\n#{exception.class}: #{exception.message}\n#{exception.backtrace.join("\n")}"
    end

    message
  end
end
