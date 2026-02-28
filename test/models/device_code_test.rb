require "test_helper"

class DeviceCodeTest < ActiveSupport::TestCase
  test "requires device_code" do
    dc = DeviceCode.new(user_code: "abc", expires_at: 15.minutes.from_now)
    refute dc.valid?
    assert_includes dc.errors[:device_code], "can't be blank"
  end

  test "requires user_code" do
    dc = DeviceCode.new(device_code: "ABCDEFGH", expires_at: 15.minutes.from_now)
    refute dc.valid?
    assert_includes dc.errors[:user_code], "can't be blank"
  end

  test "requires expires_at" do
    dc = DeviceCode.new(device_code: "ABCDEFGH", user_code: "abc")
    refute dc.valid?
    assert_includes dc.errors[:expires_at], "can't be blank"
  end

  test "enforces uniqueness of device_code" do
    existing = device_codes(:pending)
    duplicate = DeviceCode.new(
      device_code: existing.device_code,
      user_code: "unique_code",
      expires_at: 15.minutes.from_now
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:device_code], "has already been taken"
  end

  test "enforces uniqueness of user_code" do
    existing = device_codes(:pending)
    duplicate = DeviceCode.new(
      device_code: "UNIQCODE",
      user_code: existing.user_code,
      expires_at: 15.minutes.from_now
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:user_code], "has already been taken"
  end

  test "user is optional" do
    dc = device_codes(:pending)
    assert_nil dc.user
    assert dc.valid?
  end

  test "confirmed? returns true when confirmed_at is set" do
    dc = device_codes(:confirmed)
    assert dc.confirmed?
  end

  test "confirmed? returns false when confirmed_at is nil" do
    dc = device_codes(:pending)
    refute dc.confirmed?
  end

  test "expired? returns true when expires_at is in the past" do
    dc = device_codes(:expired)
    assert dc.expired?
  end

  test "expired? returns false when expires_at is in the future" do
    dc = device_codes(:pending)
    refute dc.expired?
  end

  test "belongs to user when confirmed" do
    dc = device_codes(:confirmed)
    assert_equal users(:one), dc.user
  end
end
