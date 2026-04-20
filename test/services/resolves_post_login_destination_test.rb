# frozen_string_literal: true

require "test_helper"

class ResolvesPostLoginDestinationTest < ActiveSupport::TestCase
  test "premium_monthly plan returns checkout path with monthly price_id" do
    result = ResolvesPostLoginDestination.call(plan: "premium_monthly")

    assert_equal "/checkout?price_id=#{AppConfig::Stripe::PRICE_ID_MONTHLY}", result
  end

  test "premium_annual plan returns checkout path with annual price_id" do
    result = ResolvesPostLoginDestination.call(plan: "premium_annual")

    assert_equal "/checkout?price_id=#{AppConfig::Stripe::PRICE_ID_ANNUAL}", result
  end

  test "credit_pack plan returns checkout path with first pack size" do
    result = ResolvesPostLoginDestination.call(plan: "credit_pack")

    first_pack_size = AppConfig::Credits::PACKS.first[:size]
    assert_equal "/checkout?pack_size=#{first_pack_size}", result
  end

  test "nil plan returns nil so the controller can fall back to after_authentication_url" do
    result = ResolvesPostLoginDestination.call(plan: nil)

    assert_nil result
  end

  test "unknown plan returns nil so the controller can fall back to after_authentication_url" do
    result = ResolvesPostLoginDestination.call(plan: "some_unknown_plan")

    assert_nil result
  end

  test "empty string plan returns nil" do
    result = ResolvesPostLoginDestination.call(plan: "")

    assert_nil result
  end
end
