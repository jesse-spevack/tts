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
    data_struct = Struct.new(:name, :value, keyword_init: true)
    data = data_struct.new(name: "test", value: 42)

    result = Result.success(data)

    assert result.success?
    assert_equal "test", result.data.name
    assert_equal 42, result.data.value
  end

  test "success with nil data and kwargs stores kwargs as data" do
    result = Result.success(nil, remaining: 5)

    assert result.success?
    assert_equal({ remaining: 5 }, result.data)
  end

  test "success with kwargs only stores kwargs as data" do
    result = Result.success(remaining: 5, processed: 10)

    assert result.success?
    assert_equal({ remaining: 5, processed: 10 }, result.data)
  end

  test "success with data ignores kwargs" do
    result = Result.success("my_data", remaining: 5)

    assert result.success?
    assert_equal "my_data", result.data
  end

  test "success accepts optional message" do
    result = Result.success("data", message: "Operation completed")

    assert result.success?
    assert_equal "Operation completed", result.message
  end

  test "failure sets message to error by default" do
    result = Result.failure("error")

    assert_equal "error", result.message
  end

  test "failure accepts optional message" do
    result = Result.failure("error", message: "User message")

    assert_equal "error", result.error
    assert_equal "User message", result.message
  end

  test "flash_type returns notice for success" do
    result = Result.success("data")

    assert_equal :notice, result.flash_type
  end

  test "flash_type returns alert for failure" do
    result = Result.failure("error")

    assert_equal :alert, result.flash_type
  end
end
