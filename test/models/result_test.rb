# frozen_string_literal: true

require "test_helper"

class ResultTest < ActiveSupport::TestCase
  test "success creates successful result with data" do
    result = Result.success("hello")

    assert result.success?
    refute result.failure?
    assert_equal "hello", result.data
    assert_nil result.error
  end

  test "success works with nil data" do
    result = Result.success(nil)

    assert result.success?
    assert_nil result.data
  end

  test "failure creates failed result with error" do
    result = Result.failure("boom")

    refute result.success?
    assert result.failure?
    assert_nil result.data
    assert_equal "boom", result.error
  end

  test "results are frozen" do
    result = Result.success("data")

    assert result.frozen?
  end

  test "success works with struct data" do
    TestData = Struct.new(:name, :value, keyword_init: true)
    data = TestData.new(name: "test", value: 42)

    result = Result.success(data)

    assert result.success?
    assert_equal "test", result.data.name
    assert_equal 42, result.data.value
  end
end
