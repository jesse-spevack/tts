require "test_helper"

class ValidatesPriceTest < ActiveSupport::TestCase
  test "returns success for monthly price" do
    result = ValidatesPrice.call(AppConfig::Stripe::PRICE_ID_MONTHLY)
    assert result.success?
    assert_equal AppConfig::Stripe::PRICE_ID_MONTHLY, result.data
  end

  test "returns success for annual price" do
    result = ValidatesPrice.call(AppConfig::Stripe::PRICE_ID_ANNUAL)
    assert result.success?
    assert_equal AppConfig::Stripe::PRICE_ID_ANNUAL, result.data
  end

  test "returns failure for invalid price" do
    result = ValidatesPrice.call("price_invalid")
    assert result.failure?
    assert_equal "Invalid price selected", result.error
  end

  test "returns failure for nil" do
    result = ValidatesPrice.call(nil)
    assert result.failure?
    assert_equal "Invalid price selected", result.error
  end

  test "credit_pack? returns false for subscription price" do
    refute ValidatesPrice.credit_pack?(AppConfig::Stripe::PRICE_ID_MONTHLY)
  end

  # --- Multi-pack credit price ids (agent-team-qc7t) ---
  # The three new pack SKUs (5/10/20) must all validate as acceptable prices
  # and be recognized as credit-pack prices so CreatesCheckoutSession picks
  # the 'payment' checkout mode for them.

  test "returns success for each of the three credit pack price ids" do
    AppConfig::Credits::PACKS.each do |pack|
      result = ValidatesPrice.call(pack[:stripe_price_id])
      assert result.success?, "expected #{pack[:label]} price to validate"
      assert_equal pack[:stripe_price_id], result.data
    end
  end

  test "credit_pack? returns true for each of the three credit pack price ids" do
    AppConfig::Credits::PACKS.each do |pack|
      assert ValidatesPrice.credit_pack?(pack[:stripe_price_id]),
        "expected credit_pack? to be true for #{pack[:label]}"
    end
  end

  test "credit_pack? returns false for unknown price id" do
    refute ValidatesPrice.credit_pack?("price_unknown_random")
  end

  # The old single-pack SKU ($4.99 / 5) was retired when the 5/10/20 ladder
  # shipped. A legacy price id must now reject so no stale form or link can
  # route users to a dead SKU.
  test "legacy single-pack price id is no longer valid" do
    legacy_id = "price_legacy_credit_pack_499"
    result = ValidatesPrice.call(legacy_id)
    assert result.failure?, "legacy single-pack price id must not validate"
    refute ValidatesPrice.credit_pack?(legacy_id)
  end
end
