require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "with_valid_auth_token scope returns users with valid tokens" do
    user_with_valid_token = users(:one)
    user_with_valid_token.update!(
      auth_token: "valid_token",
      auth_token_expires_at: 30.minutes.from_now
    )

    user_with_expired_token = users(:two)
    user_with_expired_token.update!(
      auth_token: "expired_token",
      auth_token_expires_at: 1.hour.ago
    )

    valid_users = User.with_valid_auth_token

    assert_includes valid_users, user_with_valid_token
    assert_not_includes valid_users, user_with_expired_token
  end

  test "with_valid_auth_token scope excludes users with nil token" do
    user_without_token = users(:one)
    user_without_token.update!(auth_token: nil, auth_token_expires_at: 30.minutes.from_now)

    valid_users = User.with_valid_auth_token

    assert_not_includes valid_users, user_without_token
  end

  test "with_valid_auth_token scope excludes users with nil expiration" do
    user_without_expiration = users(:one)
    user_without_expiration.update!(auth_token: "token", auth_token_expires_at: nil)

    valid_users = User.with_valid_auth_token

    assert_not_includes valid_users, user_without_expiration
  end

  test "defaults to free tier" do
    user = User.new(email_address: "test@example.com")
    assert user.free?
  end

  test "can set tier to basic" do
    user = users(:one)
    user.update!(tier: :basic)
    assert user.basic?
  end

  test "can set tier to plus" do
    user = users(:one)
    user.update!(tier: :plus)
    assert user.plus?
  end

  test "can set tier to premium" do
    user = users(:one)
    user.update!(tier: :premium)
    assert user.premium?
  end

  test "can set tier to unlimited" do
    user = users(:one)
    user.update!(tier: :unlimited)
    assert user.unlimited?
  end

  test "submissions_enabled? returns true for unlimited tier" do
    user = users(:one)
    user.update!(tier: :unlimited)
    assert user.submissions_enabled?
  end

  test "submissions_enabled? returns false for free tier" do
    user = users(:one)
    user.update!(tier: :free)
    assert_not user.submissions_enabled?
  end

  test "submissions_enabled? returns false for basic tier" do
    user = users(:one)
    user.update!(tier: :basic)
    assert_not user.submissions_enabled?
  end

  test "submissions_enabled? returns false for plus tier" do
    user = users(:one)
    user.update!(tier: :plus)
    assert_not user.submissions_enabled?
  end

  test "submissions_enabled? returns false for premium tier" do
    user = users(:one)
    user.update!(tier: :premium)
    assert_not user.submissions_enabled?
  end

  test "email returns email_address" do
    user = users(:one)
    assert_equal user.email_address, user.email
  end
end
