# frozen_string_literal: true

require "test_helper"

class TransientAudioErrorsTest < ActiveSupport::TestCase
  test "identifies Google Cloud DeadlineExceededError as transient" do
    assert TransientAudioErrors.transient?(Google::Cloud::DeadlineExceededError.new("timeout"))
  end

  test "identifies Google Cloud UnavailableError as transient" do
    assert TransientAudioErrors.transient?(Google::Cloud::UnavailableError.new("unavailable"))
  end

  test "identifies Google Cloud InternalError as transient" do
    assert TransientAudioErrors.transient?(Google::Cloud::InternalError.new("internal"))
  end

  test "identifies Faraday TimeoutError as transient" do
    assert TransientAudioErrors.transient?(Faraday::TimeoutError.new("timeout"))
  end

  test "identifies Faraday ConnectionFailed as transient" do
    assert TransientAudioErrors.transient?(Faraday::ConnectionFailed.new("connection failed"))
  end

  test "does not identify StandardError as transient" do
    refute TransientAudioErrors.transient?(StandardError.new("generic"))
  end

  test "does not identify ResourceExhaustedError as transient" do
    refute TransientAudioErrors.transient?(Google::Cloud::ResourceExhaustedError.new("quota"))
  end

  test "does not identify InvalidArgumentError as transient" do
    refute TransientAudioErrors.transient?(Google::Cloud::InvalidArgumentError.new("bad input"))
  end
end
