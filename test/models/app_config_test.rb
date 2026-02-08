# frozen_string_literal: true

require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  test "FREE_CHARACTER_LIMIT is 15000" do
    assert_equal 15_000, AppConfig::Tiers::FREE_CHARACTER_LIMIT
  end

  test "PREMIUM_CHARACTER_LIMIT is 50000" do
    assert_equal 50_000, AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT
  end

  test "FREE_MONTHLY_EPISODES is 2" do
    assert_equal 2, AppConfig::Tiers::FREE_MONTHLY_EPISODES
  end

  test "character_limit_for free tier returns FREE_CHARACTER_LIMIT" do
    assert_equal 15_000, AppConfig::Tiers.character_limit_for("free")
  end

  test "character_limit_for premium tier returns PREMIUM_CHARACTER_LIMIT" do
    assert_equal 50_000, AppConfig::Tiers.character_limit_for("premium")
  end

  test "character_limit_for unlimited tier returns nil" do
    assert_nil AppConfig::Tiers.character_limit_for("unlimited")
  end

  test "FREE_VOICES contains eight standard voices" do
    assert_equal %w[wren felix sloane archer gemma hugo quinn theo], AppConfig::Tiers::FREE_VOICES
  end

  test "UNLIMITED_VOICES contains all twelve voices" do
    assert_equal 12, AppConfig::Tiers::UNLIMITED_VOICES.length
    assert_includes AppConfig::Tiers::UNLIMITED_VOICES, "wren"
    assert_includes AppConfig::Tiers::UNLIMITED_VOICES, "elara"
  end

  test "voices_for free tier returns FREE_VOICES" do
    assert_equal AppConfig::Tiers::FREE_VOICES, AppConfig::Tiers.voices_for("free")
  end

  test "voices_for premium tier returns FREE_VOICES" do
    assert_equal AppConfig::Tiers::FREE_VOICES, AppConfig::Tiers.voices_for("premium")
  end

  test "voices_for unlimited tier returns UNLIMITED_VOICES" do
    assert_equal AppConfig::Tiers::UNLIMITED_VOICES, AppConfig::Tiers.voices_for("unlimited")
  end

  test "Content::MIN_LENGTH is 100" do
    assert_equal 100, AppConfig::Content::MIN_LENGTH
  end

  test "Content::MAX_FETCH_BYTES is 10MB" do
    assert_equal 10 * 1024 * 1024, AppConfig::Content::MAX_FETCH_BYTES
  end

  test "Llm::MAX_TITLE_LENGTH is 255" do
    assert_equal 255, AppConfig::Llm::MAX_TITLE_LENGTH
  end

  test "Llm::MAX_AUTHOR_LENGTH is 255" do
    assert_equal 255, AppConfig::Llm::MAX_AUTHOR_LENGTH
  end

  test "Llm::MAX_DESCRIPTION_LENGTH is 1000" do
    assert_equal 1000, AppConfig::Llm::MAX_DESCRIPTION_LENGTH
  end

  test "Network::TIMEOUT_SECONDS is 10" do
    assert_equal 10, AppConfig::Network::TIMEOUT_SECONDS
  end

  test "Network::DNS_TIMEOUT_SECONDS is 5" do
    assert_equal 5, AppConfig::Network::DNS_TIMEOUT_SECONDS
  end

  test "Stripe module has price constants" do
    assert_equal "test_price_monthly", AppConfig::Stripe::PRICE_ID_MONTHLY
    assert_equal "test_price_annual", AppConfig::Stripe::PRICE_ID_ANNUAL
  end

  test "Storage.public_feed_url returns branded URL" do
    result = AppConfig::Storage.public_feed_url("podcast_abc123")

    assert_equal "https://example.com/feeds/podcast_abc123.xml", result
  end

  test "Storage.feed_url returns GCS URL" do
    result = AppConfig::Storage.feed_url("podcast_abc123")

    expected = "https://storage.googleapis.com/#{AppConfig::Storage::BUCKET}/podcasts/podcast_abc123/feed.xml"
    assert_equal expected, result
  end
end
