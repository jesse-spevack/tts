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

  test "returns success for credit pack price" do
    result = ValidatesPrice.call(AppConfig::Stripe::PRICE_ID_CREDIT_PACK)
    assert result.success?
    assert_equal AppConfig::Stripe::PRICE_ID_CREDIT_PACK, result.data
  end

  test "returns failure for nil" do
    result = ValidatesPrice.call(nil)
    assert result.failure?
    assert_equal "Invalid price selected", result.error
  end

  test "credit_pack? returns true for credit pack price" do
    assert ValidatesPrice.credit_pack?(AppConfig::Stripe::PRICE_ID_CREDIT_PACK)
  end

  test "credit_pack? returns false for subscription price" do
    refute ValidatesPrice.credit_pack?(AppConfig::Stripe::PRICE_ID_MONTHLY)
  end

  test "subscription? returns true for monthly price" do
    assert ValidatesPrice.subscription?(AppConfig::Stripe::PRICE_ID_MONTHLY)
  end

  test "subscription? returns false for credit pack price" do
    refute ValidatesPrice.subscription?(AppConfig::Stripe::PRICE_ID_CREDIT_PACK)
  end
end
