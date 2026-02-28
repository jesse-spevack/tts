require "test_helper"

class CreatesDeviceCodeTest < ActiveSupport::TestCase
  test "creates a device code" do
    assert_difference "DeviceCode.count", 1 do
      CreatesDeviceCode.call
    end
  end

  test "returns a DeviceCode record" do
    result = CreatesDeviceCode.call
    assert_kind_of DeviceCode, result
    assert result.persisted?
  end

  test "sets device_code as 8 uppercase letters" do
    result = CreatesDeviceCode.call
    assert_match(/\A[A-Z]{8}\z/, result.device_code)
  end

  test "excludes ambiguous characters from device_code" do
    # Generate many codes to increase probability of catching bad chars
    100.times do
      result = CreatesDeviceCode.call
      refute_match(/[OIL01]/, result.device_code)
    end
  end

  test "sets a user_code" do
    result = CreatesDeviceCode.call
    assert result.user_code.present?
  end

  test "user_code is a string longer than 10 characters" do
    result = CreatesDeviceCode.call
    assert_kind_of String, result.user_code
    assert result.user_code.length > 10
  end

  test "sets expires_at to 15 minutes from now" do
    freeze_time do
      result = CreatesDeviceCode.call
      assert_in_delta 15.minutes.from_now, result.expires_at, 1.second
    end
  end

  test "does not set user" do
    result = CreatesDeviceCode.call
    assert_nil result.user
  end

  test "does not set token" do
    result = CreatesDeviceCode.call
    assert_nil result.token
  end
end
