require "test_helper"

class ValidatesPriceTest < ActiveSupport::TestCase
  # Subscription price ids were retired as valid checkout inputs in the
  # 2026-04 pricing pivot (agent-team-633o) and the subscription code was
  # fully removed in agent-team-9rt7. Only credit-pack price ids now
  # validate as acceptable checkout inputs.

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

  # The old single-pack SKU ($4.99 / 5) was retired when the 5/10/20 ladder
  # shipped. A legacy price id must now reject so no stale form or link can
  # route users to a dead SKU.
  test "legacy single-pack price id is no longer valid" do
    legacy_id = "price_legacy_credit_pack_499"
    result = ValidatesPrice.call(legacy_id)
    assert result.failure?, "legacy single-pack price id must not validate"
  end
end
