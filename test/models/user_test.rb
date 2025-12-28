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

  test "email returns email_address" do
    user = users(:one)
    assert_equal user.email_address, user.email
  end

  test "voice returns Standard voice for free tier with no preference" do
    user = users(:one)
    user.tier = :free
    user.voice_preference = nil

    assert_equal "en-GB-Standard-D", user.voice
  end

  test "voice returns Standard voice for premium tier with no preference" do
    user = users(:one)
    user.tier = :premium
    user.voice_preference = nil

    assert_equal "en-GB-Standard-D", user.voice
  end

  test "voice returns Chirp3-HD voice for unlimited tier with no preference" do
    user = users(:one)
    user.tier = :unlimited
    user.voice_preference = nil

    assert_equal "en-GB-Chirp3-HD-Enceladus", user.voice
  end

  test "voice_preference validates inclusion in Voice::ALL" do
    user = users(:one)
    user.voice_preference = "invalid_voice"

    assert_not user.valid?
    assert_includes user.errors[:voice_preference], "is not included in the list"
  end

  test "voice_preference allows nil" do
    user = users(:one)
    user.voice_preference = nil

    assert user.valid?
  end

  test "voice_preference allows valid standard voice" do
    user = users(:one)
    user.voice_preference = "wren"

    assert user.valid?
  end

  test "voice_preference allows valid chirp voice" do
    user = users(:one)
    user.voice_preference = "elara"

    assert user.valid?
  end

  test "voice returns google_voice for selected voice_preference" do
    user = users(:one)
    user.voice_preference = "wren"

    assert_equal "en-GB-Standard-C", user.voice
  end

  test "voice returns default Standard voice when voice_preference is nil and tier is free" do
    user = users(:one)
    user.tier = :free
    user.voice_preference = nil

    assert_equal Voice::DEFAULT_STANDARD, user.voice
  end

  test "voice returns default Chirp voice when voice_preference is nil and tier is unlimited" do
    user = users(:one)
    user.tier = :unlimited
    user.voice_preference = nil

    assert_equal Voice::DEFAULT_CHIRP, user.voice
  end

  test "voice returns default when voice_preference is invalid" do
    user = users(:one)
    user.tier = :free
    # Bypass validation to simulate corrupted data
    user.write_attribute(:voice_preference, "invalid_voice")

    assert_equal Voice::DEFAULT_STANDARD, user.voice
  end

  test "available_voices returns FREE_VOICES for free tier" do
    user = users(:one)
    user.tier = :free

    assert_equal AppConfig::Tiers::FREE_VOICES, user.available_voices
  end

  test "available_voices returns UNLIMITED_VOICES for unlimited tier" do
    user = users(:one)
    user.tier = :unlimited

    assert_equal AppConfig::Tiers::UNLIMITED_VOICES, user.available_voices
  end
end
