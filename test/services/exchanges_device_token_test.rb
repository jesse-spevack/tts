require "test_helper"

class ExchangesDeviceTokenTest < ActiveSupport::TestCase
  test "returns access_token for confirmed code" do
    dc = device_codes(:confirmed)

    result = ExchangesDeviceToken.call(device_code: dc)

    assert result.success?
    assert result.data[:access_token].present?
    assert result.data[:access_token].start_with?("sk_live_")
    assert_equal users(:one).email_address, result.data[:user_email]
  end

  test "stores token_digest after exchange" do
    dc = device_codes(:confirmed)

    ExchangesDeviceToken.call(device_code: dc)

    dc.reload
    assert dc.token_digest.present?
  end

  test "returned token is a valid API token" do
    dc = device_codes(:confirmed)

    result = ExchangesDeviceToken.call(device_code: dc)

    api_token = FindsApiToken.call(plain_token: result.data[:access_token])
    assert_not_nil api_token
    assert_equal users(:one), api_token.user
    assert api_token.active?
  end

  test "returns failure for expired code" do
    dc = device_codes(:expired)

    result = ExchangesDeviceToken.call(device_code: dc)

    assert result.failure?
    assert_equal "expired_token", result.error
  end

  test "returns failure for unconfirmed code" do
    dc = device_codes(:pending)

    result = ExchangesDeviceToken.call(device_code: dc)

    assert result.failure?
    assert_equal "authorization_pending", result.error
  end

  test "returns failure for already exchanged code" do
    dc = device_codes(:exchanged)

    result = ExchangesDeviceToken.call(device_code: dc)

    assert result.failure?
    assert_equal "expired_token", result.error
  end

  test "prevents double exchange under concurrency" do
    dc = device_codes(:confirmed)

    first_result = ExchangesDeviceToken.call(device_code: dc)
    second_result = ExchangesDeviceToken.call(device_code: dc)

    assert first_result.success?
    assert second_result.failure?
    assert_equal "expired_token", second_result.error
  end
end
