require "test_helper"

class ConfirmsDeviceCodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "confirms a pending device code" do
    dc = device_codes(:pending)

    result = ConfirmsDeviceCode.call(device_code: dc, user: @user)

    assert result.success?
    dc.reload
    assert dc.confirmed?
    assert_equal @user, dc.user
  end

  test "returns failure for expired device code" do
    dc = device_codes(:expired)

    result = ConfirmsDeviceCode.call(device_code: dc, user: @user)

    assert result.failure?
    assert_match(/expired/, result.error)
  end

  test "returns failure for already confirmed device code" do
    dc = device_codes(:confirmed)

    result = ConfirmsDeviceCode.call(device_code: dc, user: @user)

    assert result.failure?
    assert_match(/already been used/, result.error)
  end

  test "sets confirmed_at timestamp" do
    dc = device_codes(:pending)

    freeze_time do
      ConfirmsDeviceCode.call(device_code: dc, user: @user)

      dc.reload
      assert_equal Time.current, dc.confirmed_at
    end
  end

  test "does not store plaintext token" do
    dc = device_codes(:pending)

    ConfirmsDeviceCode.call(device_code: dc, user: @user)

    dc.reload
    assert_nil dc.token_digest
  end
end
