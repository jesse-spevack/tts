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

  test "email returns email_address" do
    user = users(:one)
    assert_equal user.email_address, user.email
  end

  # Account type enum tests
  test "account_type enum has correct values" do
    assert_equal({ "standard" => 0, "complimentary" => 1, "unlimited" => 2 }, User.account_types)
  end

  test "defaults to standard account_type" do
    user = User.new(email_address: "test@example.com")
    assert user.standard?
  end

  test "can set account_type to complimentary" do
    user = users(:one)
    user.update!(account_type: :complimentary)
    assert user.complimentary?
  end

  test "can set account_type to unlimited" do
    user = users(:one)
    user.update!(account_type: :unlimited)
    assert user.unlimited?
  end

  # Premium/Free status tests
  test "premium? returns true for user with active subscription" do
    user = users(:subscriber)
    assert user.premium?
  end

  test "premium? returns false for user without subscription" do
    user = users(:free_user)
    refute user.premium?
  end

  test "premium? returns true for complimentary user" do
    user = users(:complimentary_user)
    assert user.premium?
  end

  test "premium? returns true for unlimited user" do
    user = users(:unlimited_user)
    assert user.premium?
  end

  test "premium? returns false for user with canceled subscription" do
    user = users(:canceled_subscriber)
    refute user.premium?
  end

  test "free? returns true for standard user without subscription" do
    user = users(:free_user)
    assert user.free?
  end

  test "free? returns false for user with active subscription" do
    user = users(:subscriber)
    refute user.free?
  end

  test "free? returns false for complimentary user" do
    user = users(:complimentary_user)
    refute user.free?
  end

  test "free? returns false for unlimited user" do
    user = users(:unlimited_user)
    refute user.free?
  end

  # Voice tests
  test "voice returns Standard voice for free user with no preference" do
    user = users(:free_user)
    user.voice_preference = nil

    assert_equal "en-GB-Standard-D", user.voice
  end

  test "voice returns Chirp3-HD voice for unlimited user with no preference" do
    user = users(:unlimited_user)
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

  test "voice returns default Standard voice when voice_preference is nil and user is free" do
    user = users(:free_user)
    user.voice_preference = nil

    assert_equal Voice::DEFAULT_STANDARD, user.voice
  end

  test "voice returns default Chirp voice when voice_preference is nil and user is unlimited" do
    user = users(:unlimited_user)
    user.voice_preference = nil

    assert_equal Voice::DEFAULT_CHIRP, user.voice
  end

  test "voice returns default when voice_preference is invalid" do
    user = users(:free_user)
    # Bypass validation to simulate corrupted data
    user.write_attribute(:voice_preference, "invalid_voice")

    assert_equal Voice::DEFAULT_STANDARD, user.voice
  end

  # primary_podcast tests
  test "primary_podcast returns first podcast for user with podcasts" do
    user = users(:one)
    podcast = podcasts(:one)

    assert_equal podcast, user.primary_podcast
  end

  test "primary_podcast creates default podcast for user without podcasts" do
    user = User.create!(email_address: "newuser@example.com")

    assert_difference "Podcast.count", 1 do
      podcast = user.primary_podcast
      assert podcast.persisted?
      assert_includes podcast.title, user.email_address
    end
  end

  # email_episode_confirmation tests
  test "email_episode_confirmation defaults to true" do
    user = User.new(email_address: "test@example.com")
    # The default is set in the database, so we need to save and reload
    user.save!
    user.reload

    assert user.email_episode_confirmation?
  end

  test "email_episode_confirmation can be set to false" do
    user = users(:two)

    refute user.email_episode_confirmation?
  end

  test "available_voices returns FREE_VOICES for free user" do
    user = users(:free_user)

    assert_equal AppConfig::Tiers::FREE_VOICES, user.available_voices
  end

  test "available_voices returns UNLIMITED_VOICES for unlimited user" do
    user = users(:unlimited_user)

    assert_equal AppConfig::Tiers::UNLIMITED_VOICES, user.available_voices
  end

  test "available_voices returns PREMIUM_VOICES for premium user" do
    user = users(:subscriber)

    assert_equal AppConfig::Tiers::PREMIUM_VOICES, user.available_voices
  end

  # email_ingest_address tests
  test "email_ingest_address delegates to GeneratesEmailIngestAddress service" do
    user = users(:one)
    EnablesEmailEpisodes.call(user: user)

    assert_equal GeneratesEmailIngestAddress.call(user: user), user.email_ingest_address
  end

  test "email_ingest_address returns nil for user without email_ingest_token" do
    user = users(:one)
    user.update!(email_ingest_token: nil)

    assert_nil user.email_ingest_address
  end
end
