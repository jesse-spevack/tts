require "test_helper"

class EpisodesHelperTest < ActionView::TestCase
  test "status_badge returns processing badge with pulse animation" do
    result = status_badge("processing")
    assert_includes result, "Processing"
    assert_includes result, "animate-pulse"
    assert_includes result, "var(--color-yellow)"
  end

  test "status_badge returns completed badge with checkmark" do
    result = status_badge("complete")
    assert_includes result, "Completed"
    assert_includes result, "✓"
    assert_includes result, "var(--color-green)"
  end

  test "status_badge returns failed badge with X" do
    result = status_badge("failed")
    assert_includes result, "Failed"
    assert_includes result, "✗"
    assert_includes result, "var(--color-red)"
  end

  test "status_badge returns pending badge" do
    result = status_badge("pending")
    assert_includes result, "Pending"
    assert_includes result, "var(--color-yellow)"
  end
end
