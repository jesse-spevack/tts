require "test_helper"

class ResolvesCreditPackTest < ActiveSupport::TestCase
  test "returns success for '5' and returns the 5-pack hash" do
    result = ResolvesCreditPack.call("5")
    assert result.success?
    assert_equal 5, result.data[:size]
    assert_equal AppConfig::Credits.find_pack_by_size(5), result.data
  end

  test "returns success for '10' and returns the 10-pack hash" do
    result = ResolvesCreditPack.call("10")
    assert result.success?
    assert_equal 10, result.data[:size]
    assert_equal AppConfig::Credits.find_pack_by_size(10), result.data
  end

  test "returns success for '20' and returns the 20-pack hash" do
    result = ResolvesCreditPack.call("20")
    assert result.success?
    assert_equal 20, result.data[:size]
    assert_equal AppConfig::Credits.find_pack_by_size(20), result.data
  end

  test "returns failure for an unknown pack size" do
    result = ResolvesCreditPack.call("7")
    assert result.failure?
    assert_equal "Invalid credit pack selected", result.error
  end

  test "returns failure for a non-numeric string" do
    result = ResolvesCreditPack.call("abc")
    assert result.failure?
    assert_equal "Invalid credit pack selected", result.error
  end

  test "returns failure for an empty string" do
    result = ResolvesCreditPack.call("")
    assert result.failure?
    assert_equal "Invalid credit pack selected", result.error
  end

  test "returns failure for nil" do
    result = ResolvesCreditPack.call(nil)
    assert result.failure?
    assert_equal "Invalid credit pack selected", result.error
  end

  test "returns success when given an Integer pack size" do
    result = ResolvesCreditPack.call(5)
    assert result.success?
    assert_equal 5, result.data[:size]
  end
end
