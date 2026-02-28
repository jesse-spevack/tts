require "test_helper"

class CleanupExpiredDeviceCodesJobTest < ActiveSupport::TestCase
  test "deletes expired device codes" do
    # expired fixture has expires_at in the past
    assert DeviceCode.where("expires_at < ?", Time.current).exists?

    assert_difference "DeviceCode.count", -1 do
      CleanupExpiredDeviceCodesJob.perform_now
    end
  end

  test "does not delete non-expired device codes" do
    pending_code = device_codes(:pending)

    CleanupExpiredDeviceCodesJob.perform_now

    assert DeviceCode.exists?(pending_code.id)
  end

  test "does not delete confirmed non-expired device codes" do
    confirmed_code = device_codes(:confirmed)

    CleanupExpiredDeviceCodesJob.perform_now

    assert DeviceCode.exists?(confirmed_code.id)
  end
end
