# frozen_string_literal: true

module StructuredLogging
  extend ActiveSupport::Concern

  private

  def log_info(event, **attrs)
    Rails.logger.info build_log_message(event, attrs)
  end

  def log_warn(event, **attrs)
    Rails.logger.warn build_log_message(event, attrs)
  end

  def log_error(event, **attrs)
    Rails.logger.error build_log_message(event, attrs)
  end

  def default_log_context
    { action_id: Current.action_id }.compact
  end

  def build_log_message(event, attrs)
    context = default_log_context.merge(attrs)
    parts = ["event=#{event}"]
    context.each { |k, v| parts << "#{k}=#{v}" if v.present? }
    parts.join(" ")
  end
end
