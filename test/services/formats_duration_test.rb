# frozen_string_literal: true

require "test_helper"

class FormatsDurationTest < ActiveSupport::TestCase
  test "formats seconds into MM:SS" do
    assert_equal "1:30", FormatsDuration.call(90)
  end

  test "pads seconds with zero" do
    assert_equal "2:05", FormatsDuration.call(125)
  end

  test "handles zero" do
    assert_equal "0:00", FormatsDuration.call(0)
  end

  test "returns nil for nil input" do
    assert_nil FormatsDuration.call(nil)
  end

  test "handles large durations" do
    assert_equal "120:00", FormatsDuration.call(7200)
  end
end
