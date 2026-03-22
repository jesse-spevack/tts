# frozen_string_literal: true

require "json"
require "logger"

# Formats log output as JSON compatible with Google Cloud Logging's structured logging format.
# See: https://cloud.google.com/logging/docs/structured-logging
#
# When used with ActiveSupport::TaggedLogging, request tags (like request_id)
# are included in the JSON labels rather than prepended to the message string.
#
# Cloud Error Reporting picks up errors automatically when the message contains
# a Ruby-style backtrace (ErrorClass: message\n  path:line:in `method'...).
class CloudLoggingFormatter < Logger::Formatter
  SEVERITY_MAP = {
    "DEBUG"   => "DEBUG",
    "INFO"    => "INFO",
    "WARN"    => "WARNING",
    "ERROR"   => "ERROR",
    "FATAL"   => "CRITICAL",
    "UNKNOWN" => "DEFAULT"
  }.freeze

  def call(severity, time, _progname, message)
    msg = message_to_s(message)

    entry = {
      severity: SEVERITY_MAP.fetch(severity, severity),
      timestamp: time.utc.iso8601(3),
      message: strip_tags(msg)
    }

    if respond_to?(:current_tags) && current_tags.present?
      entry[:"logging.googleapis.com/labels"] = tags_as_labels
    end

    "#{entry.to_json}\n"
  end

  private

  def message_to_s(message)
    case message
    when String then message
    when nil    then ""
    else             message.inspect
    end
  end

  def strip_tags(message)
    message.sub(/\A(\[[^\]]*\] )*/, "")
  end

  def tags_as_labels
    tags = current_tags
    labels = {}
    labels[:request_id] = tags.first if tags.first.present?
    tags.drop(1).each_with_index { |tag, i| labels[:"tag_#{i}"] = tag }
    labels
  end
end
