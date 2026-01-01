require "test_helper"

class ValidatesPriceTest < ActiveSupport::TestCase
  test "returns true for monthly price" do
    assert ValidatesPrice.call(AppConfig::Stripe::PRICE_ID_MONTHLY)
  end

  test "returns true for annual price" do
    assert ValidatesPrice.call(AppConfig::Stripe::PRICE_ID_ANNUAL)
  end

  test "returns false for invalid price" do
    refute ValidatesPrice.call("price_invalid")
  end

  test "returns false for nil" do
    refute ValidatesPrice.call(nil)
  end
end
