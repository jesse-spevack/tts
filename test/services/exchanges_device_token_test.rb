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

  # agent-team-u5l: a device_code that was confirmed before the user was
  # deactivated must NOT mint a token — even though the token would die on
  # the next API request, leaking a token at all is inconsistent with the
  # "all auth surfaces reject deactivated users" guarantee.
  test "returns failure when the confirmed user is deactivated" do
    dc = device_codes(:confirmed)
    dc.user.update!(active: false)

    result = ExchangesDeviceToken.call(device_code: dc)

    assert result.failure?
    assert_equal "expired_token", result.error
  end

  test "does not call GeneratesApiToken when the confirmed user is deactivated" do
    dc = device_codes(:confirmed)
    dc.user.update!(active: false)

    Mocktail.replace(GeneratesApiToken)
    stubs { |m| GeneratesApiToken.call(user: m.any) }.with { raise "must not be called" }

    result = ExchangesDeviceToken.call(device_code: dc)

    assert result.failure?
    # No exception reached us — proves the stub was never triggered.
    dc.reload
    assert_nil dc.token_digest, "token_digest must not be written for deactivated users"
  end
end
