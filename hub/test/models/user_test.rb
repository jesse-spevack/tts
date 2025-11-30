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

  test "can set tier to pro" do
    user = users(:one)
    user.update!(tier: :pro)
    assert user.pro?
  end

  test "can set tier to unlimited" do
    user = users(:one)
    user.update!(tier: :unlimited)
    assert user.unlimited?
  end

  test "email returns email_address" do
    user = users(:one)
    assert_equal user.email_address, user.email
  end

  test "voice_name returns Standard voice for free tier" do
    user = users(:one)
    user.update!(tier: :free)
    assert_equal "en-GB-Standard-D", user.voice_name
  end

  test "voice_name returns Standard voice for pro tier" do
    user = users(:one)
    user.update!(tier: :pro)
    assert_equal "en-GB-Standard-D", user.voice_name
  end

  test "voice_name returns Chirp3-HD voice for unlimited tier" do
    user = users(:one)
    user.update!(tier: :unlimited)
    assert_equal "en-GB-Chirp3-HD-Enceladus", user.voice_name
  end
end
