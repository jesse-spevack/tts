require "test_helper"

class ValidatesAuthTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "call returns true for valid token" do
    @user.update!(
      auth_token: "valid_token",
      auth_token_expires_at: 30.minutes.from_now
    )

    assert ValidatesAuthToken.call(user: @user)
  end

  test "call returns false when token is nil" do
    @user.update!(auth_token: nil, auth_token_expires_at: 30.minutes.from_now)

    assert_not ValidatesAuthToken.call(user: @user)
  end

  test "call returns false when token is blank" do
    @user.update!(auth_token: "", auth_token_expires_at: 30.minutes.from_now)

    assert_not ValidatesAuthToken.call(user: @user)
  end

  test "call returns false when expiration is nil" do
    @user.update!(auth_token: "valid_token", auth_token_expires_at: nil)

    assert_not ValidatesAuthToken.call(user: @user)
  end

  test "call returns false when token is expired" do
    @user.update!(
      auth_token: "expired_token",
      auth_token_expires_at: 1.hour.ago
    )

    assert_not ValidatesAuthToken.call(user: @user)
  end

  test "call returns false when token expires exactly now" do
    freeze_time do
      @user.update!(
        auth_token: "token",
        auth_token_expires_at: Time.current
      )

      assert_not ValidatesAuthToken.call(user: @user)
    end
  end

  test "call returns true when token expires in 1 second" do
    @user.update!(
      auth_token: "token",
      auth_token_expires_at: 1.second.from_now
    )

    assert ValidatesAuthToken.call(user: @user)
  end
end
