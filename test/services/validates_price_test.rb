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
end
