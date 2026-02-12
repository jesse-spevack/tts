require "test_helper"

class EpisodesHelperTest < ActionView::TestCase
  test "status_badge returns processing badge with pulse animation" do
    result = status_badge("processing")
    assert_includes result, "Processing"
    assert_includes result, "animate-pulse"
    assert_includes result, "text-yellow-500"
  end

  test "status_dot returns ping animation for processing" do
    result = status_dot("processing")
    assert_includes result, "animate-ping"
    assert_includes result, "bg-yellow-500"
  end

  test "status_dot returns simple dot for other statuses" do
    result = status_dot("complete")
    assert_includes result, "bg-green-500"
    assert_includes result, "rounded-full"
    refute_includes result, "animate-ping"
  end

  test "status_badge returns completed badge with checkmark" do
    result = status_badge("complete")
    assert_includes result, "Completed"
    assert_includes result, "✓"
    assert_includes result, "text-green-600"
  end

  test "status_badge returns failed badge with X" do
    result = status_badge("failed")
    assert_includes result, "Failed"
    assert_includes result, "✗"
    assert_includes result, "text-red-600"
  end

  test "status_badge returns pending badge" do
    result = status_badge("pending")
    assert_includes result, "Pending"
    assert_includes result, "text-yellow-500"
  end

  test "format_duration formats seconds as MM:SS" do
    assert_equal "12:34", format_duration(754)
    assert_equal "0:05", format_duration(5)
    assert_equal "60:00", format_duration(3600)
  end

  test "format_duration returns nil for nil input" do
    assert_nil format_duration(nil)
  end
end
