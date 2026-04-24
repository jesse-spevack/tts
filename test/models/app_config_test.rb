# frozen_string_literal: true

require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  test "FREE_CHARACTER_LIMIT is 15000" do
    assert_equal 15_000, AppConfig::Tiers::FREE_CHARACTER_LIMIT
  end

  # --- iny7 rename: PREMIUM_CHARACTER_LIMIT → EPISODE_CHARACTER_LIMIT ---
  # Subscription is going away. The 50k cap is no longer "premium"; it's
  # the universal per-episode cap for every paying user (credit packs and
  # Jesse's legacy sub alike). Rename reflects that.

  test "EPISODE_CHARACTER_LIMIT is 50000" do
    assert_equal 50_000, AppConfig::Tiers::EPISODE_CHARACTER_LIMIT
  end

  test "legacy PREMIUM_CHARACTER_LIMIT constant is removed" do
    assert_raises(NameError) do
      AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT
    end
  end

  test "FREE_MONTHLY_EPISODES is 2" do
    assert_equal 2, AppConfig::Tiers::FREE_MONTHLY_EPISODES
  end

  test "FREE_VOICES contains eight standard voices" do
    assert_equal %w[wren felix sloane archer gemma hugo quinn theo], AppConfig::Tiers::FREE_VOICES
  end

  test "PREMIUM_VOICES contains all twelve voices" do
    assert_equal 12, AppConfig::Tiers::PREMIUM_VOICES.length
    assert_includes AppConfig::Tiers::PREMIUM_VOICES, "wren"
    assert_includes AppConfig::Tiers::PREMIUM_VOICES, "elara"
  end

  test "voices_for free tier returns FREE_VOICES" do
    assert_equal AppConfig::Tiers::FREE_VOICES, AppConfig::Tiers.voices_for("free")
  end

  test "voices_for premium tier returns PREMIUM_VOICES" do
    assert_equal AppConfig::Tiers::PREMIUM_VOICES, AppConfig::Tiers.voices_for("premium")
  end

  test "voices_for unlimited tier returns PREMIUM_VOICES" do
    assert_equal AppConfig::Tiers::PREMIUM_VOICES, AppConfig::Tiers.voices_for("unlimited")
  end

  test "Content::MIN_LENGTH is 100" do
    assert_equal 100, AppConfig::Content::MIN_LENGTH
  end

  test "Content::MAX_FETCH_BYTES is 10MB" do
    assert_equal 10 * 1024 * 1024, AppConfig::Content::MAX_FETCH_BYTES
  end

  test "Content::LOW_QUALITY_EXTRACTION_CHARS is 500" do
    assert_equal 500, AppConfig::Content::LOW_QUALITY_EXTRACTION_CHARS
  end

  test "Content::LOW_QUALITY_HTML_MIN_BYTES is 10000" do
    assert_equal 10_000, AppConfig::Content::LOW_QUALITY_HTML_MIN_BYTES
  end

  test "Content::JINA_READER_BASE_URL is https://r.jina.ai" do
    assert_equal "https://r.jina.ai", AppConfig::Content::JINA_READER_BASE_URL
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

  # --- PLAN_INFO map (agent-team-bwz) ---
  # Behavior is primarily tested via Subscription#plan_name and
  # Subscription#plan_display_price. These tests assert the module contract:
  # a frozen lookup keyed by Stripe price ID that returns nil for unknown keys.

  test "PLAN_INFO is a frozen hash" do
    assert_kind_of Hash, AppConfig::Stripe::PLAN_INFO
    assert AppConfig::Stripe::PLAN_INFO.frozen?, "PLAN_INFO must be frozen"
  end

  test "PLAN_INFO is keyed by stripe price id" do
    assert_includes AppConfig::Stripe::PLAN_INFO.keys, AppConfig::Stripe::PRICE_ID_MONTHLY
    assert_includes AppConfig::Stripe::PLAN_INFO.keys, AppConfig::Stripe::PRICE_ID_ANNUAL
  end

  test "PLAN_INFO returns nil for unknown price id" do
    assert_nil AppConfig::Stripe::PLAN_INFO["price_does_not_exist"]
  end

  # --- Credits::PACKS catalog (agent-team-qc7t) ---
  # Three credit packs replace the legacy single-pack PACK_SIZE/PACK_PRICE_DISPLAY
  # constants. PACKS is the authoritative catalog used by checkout, webhook
  # routing, and settings UI. Each entry is frozen so callers can share refs
  # without fear of mutation.

  PACK_5_TEST_PRICE_ID = "price_1TO99OD8ZGZanIYEXCH3vTYw"
  PACK_10_TEST_PRICE_ID = "price_1TO9A5D8ZGZanIYE56zeSE89"
  PACK_20_TEST_PRICE_ID = "price_1TO9AMD8ZGZanIYEYnsWPXYg"

  test "Credits::PACKS is a frozen array of three hashes" do
    assert_kind_of Array, AppConfig::Credits::PACKS
    assert AppConfig::Credits::PACKS.frozen?, "PACKS must be frozen"
    assert_equal 3, AppConfig::Credits::PACKS.length
    AppConfig::Credits::PACKS.each do |pack|
      assert_kind_of Hash, pack
      assert pack.frozen?, "each pack hash must be frozen"
    end
  end

  test "Credits::PACKS entries have required keys" do
    AppConfig::Credits::PACKS.each do |pack|
      assert pack.key?(:size), "missing :size"
      assert pack.key?(:price_cents), "missing :price_cents"
      assert pack.key?(:stripe_price_id), "missing :stripe_price_id"
      assert pack.key?(:label), "missing :label"
    end
  end

  test "Credits::PACKS first entry is the 5-pack Starter at $9.99" do
    pack = AppConfig::Credits::PACKS[0]
    assert_equal 5, pack[:size]
    assert_equal 999, pack[:price_cents]
    assert_equal "Starter", pack[:label]
    assert_equal PACK_5_TEST_PRICE_ID, pack[:stripe_price_id]
  end

  test "Credits::PACKS second entry is the 10-pack Standard at $17.99" do
    pack = AppConfig::Credits::PACKS[1]
    assert_equal 10, pack[:size]
    assert_equal 1799, pack[:price_cents]
    assert_equal "Standard", pack[:label]
    assert_equal PACK_10_TEST_PRICE_ID, pack[:stripe_price_id]
  end

  test "Credits::PACKS third entry is the 20-pack Bulk at $32.99" do
    pack = AppConfig::Credits::PACKS[2]
    assert_equal 20, pack[:size]
    assert_equal 3299, pack[:price_cents]
    assert_equal "Bulk", pack[:label]
    assert_equal PACK_20_TEST_PRICE_ID, pack[:stripe_price_id]
  end

  test "Credits.find_pack_by_price_id returns 5-pack for 5-pack price id" do
    pack = AppConfig::Credits.find_pack_by_price_id(PACK_5_TEST_PRICE_ID)
    refute_nil pack
    assert_equal 5, pack[:size]
  end

  test "Credits.find_pack_by_price_id returns 10-pack for 10-pack price id" do
    pack = AppConfig::Credits.find_pack_by_price_id(PACK_10_TEST_PRICE_ID)
    refute_nil pack
    assert_equal 10, pack[:size]
  end

  test "Credits.find_pack_by_price_id returns 20-pack for 20-pack price id" do
    pack = AppConfig::Credits.find_pack_by_price_id(PACK_20_TEST_PRICE_ID)
    refute_nil pack
    assert_equal 20, pack[:size]
  end

  test "Credits.find_pack_by_price_id returns nil for nil" do
    assert_nil AppConfig::Credits.find_pack_by_price_id(nil)
  end

  test "Credits.find_pack_by_price_id returns nil for unknown price id" do
    assert_nil AppConfig::Credits.find_pack_by_price_id("price_does_not_exist")
  end

  test "legacy Credits::PACK_SIZE constant is removed" do
    assert_raises(NameError) do
      AppConfig::Credits::PACK_SIZE
    end
  end

  test "legacy Credits::PACK_PRICE_DISPLAY constant is removed" do
    assert_raises(NameError) do
      AppConfig::Credits::PACK_PRICE_DISPLAY
    end
  end

  # --- Snapshot pin for Credits::PACKS pricing (agent-team-e6hd) ---
  # Pins the [size, price_cents] pairs for every credit pack so any
  # accidental price edit from an unrelated bead is caught by test.
  # Bumped deliberately whenever a pricing-scoped bead changes pack
  # prices. Established by agent-team-e6hd.
  CREDIT_PACK_PRICING_PIN = [
    [ 5, 999 ],
    [ 10, 1799 ],
    [ 20, 3299 ]
  ].freeze

  test "Credits::PACKS pricing matches the pinned snapshot" do
    current = AppConfig::Credits::PACKS.map { |p| [ p[:size], p[:price_cents] ] }
    assert_equal CREDIT_PACK_PRICING_PIN, current,
      "Credit pack pricing has changed. If this change is intentional " \
      "and scoped to a pricing bead, bump CREDIT_PACK_PRICING_PIN to the new values."
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

  # --- Tts module (agent-team-ff05) ---

  test "Tts::COST_CENTS_PER_MILLION standard rate is 400 (= $4/M chars)" do
    assert_equal 400, AppConfig::Tts::COST_CENTS_PER_MILLION["standard"]
  end

  test "Tts::COST_CENTS_PER_MILLION premium rate is 3000 (= $30/M chars)" do
    assert_equal 3_000, AppConfig::Tts::COST_CENTS_PER_MILLION["premium"]
  end

  test "Tts.tier_for Chirp3-HD voice returns premium" do
    assert_equal "premium", AppConfig::Tts.tier_for("en-GB-Chirp3-HD-Enceladus")
    assert_equal "premium", AppConfig::Tts.tier_for("en-US-Chirp3-HD-Callirrhoe")
  end

  test "Tts.tier_for Standard voice returns standard" do
    assert_equal "standard", AppConfig::Tts.tier_for("en-GB-Standard-D")
    assert_equal "standard", AppConfig::Tts.tier_for("en-US-Standard-C")
  end

  test "Tts.tier_for unknown voice defaults to standard" do
    assert_equal "standard", AppConfig::Tts.tier_for("en-US-Neural2-F")
    assert_equal "standard", AppConfig::Tts.tier_for(nil)
    assert_equal "standard", AppConfig::Tts.tier_for("")
  end

  # --- catalog-driven lookup (agent-team-s5jo) ---

  test "Tts.tier_for returns the tier from Voice::CATALOG for every catalog entry" do
    # Every key in Voice::CATALOG must round-trip through tier_for via its
    # google_voice. This is the guard against tier_for drifting away from
    # Voice::CATALOG when new voices are added.
    Voice::CATALOG.each_key do |key|
      voice = Voice.find(key)
      expected_tier = voice.tier.to_s
      actual_tier = AppConfig::Tts.tier_for(voice.google_voice)
      assert_equal expected_tier, actual_tier,
        "Expected #{voice.google_voice} (#{key}) to resolve to #{expected_tier}, got #{actual_tier}"
    end
  end

  test "Tts.tier_for logs a structured warning when voice_id is not in Voice::CATALOG" do
    # A voice ID that matches Google's premium pattern but is not in our
    # catalog is still a drift signal — under-billing today (standard fallback)
    # is preferable to silent misclassification, but the miss must be visible.
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      AppConfig::Tts.tier_for("en-US-Neural2-F")
    ensure
      Rails.logger = original_logger
    end

    assert_match(/event=tts_tier_lookup_missed/, output.string)
    assert_match(/google_voice=en-US-Neural2-F/, output.string)
  end

  test "Tts.tier_for does not warn for blank voice_id (pre-synth path)" do
    # Blank input is the normal pre-synth path; don't spam logs.
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    begin
      AppConfig::Tts.tier_for(nil)
      AppConfig::Tts.tier_for("")
    ensure
      Rails.logger = original_logger
    end

    refute_match(/tts_tier_lookup_missed/, output.string)
  end
end
