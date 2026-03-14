# frozen_string_literal: true

module TransientAudioErrors
  TRANSIENT_ERRORS = [
    Google::Cloud::DeadlineExceededError,
    Google::Cloud::UnavailableError,
    Google::Cloud::InternalError,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed
  ].freeze

  def self.transient?(error)
    TRANSIENT_ERRORS.any? { |klass| error.is_a?(klass) }
  end
end
