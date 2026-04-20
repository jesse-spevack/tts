# frozen_string_literal: true

require "test_helper"
require "ostruct"

class GrantsCreditFromCheckoutTest < ActiveSupport::TestCase
  # --- Multi-pack credit grants (agent-team-qc7t) ---
  #
  # The checkout session object coming off a Stripe webhook carries a reference
  # to which pack was purchased. Implementer owns the exact wiring (session
  # metadata vs. Stripe::Checkout::Session.retrieve(expand: [:line_items])),
  # but either way the service must:
  #   1. Identify the pack by its stripe_price_id
  #   2. Call GrantsCredits with the matching pack.size (5, 10, or 20)
  #   3. Treat unknown price ids as a failure (do not grant credits)
  #
  # These tests encode the behavioral contract. They assume the session
  # exposes the price id via `session.metadata.price_id`; implementer may
  # also choose to read from an expanded line_items payload and that's fine
  # as long as these behaviors hold.

  setup do
    @user = users(:subscriber)
    @user.update!(stripe_customer_id: "cus_credit_#{SecureRandom.hex(4)}")
  end

  test "grants 5 credits for the 5-pack price id" do
    pack_5_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 5 }[:stripe_price_id]

    session = OpenStruct.new(
      id: "cs_pack_5_#{SecureRandom.hex(4)}",
      customer: @user.stripe_customer_id,
      metadata: OpenStruct.new(price_id: pack_5_price_id)
    )

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.success?, "expected success, got: #{result.error.inspect}"
    assert_equal 5, @user.credit_balance.reload.balance
  end

  test "grants 10 credits for the 10-pack price id" do
    pack_10_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 10 }[:stripe_price_id]

    session = OpenStruct.new(
      id: "cs_pack_10_#{SecureRandom.hex(4)}",
      customer: @user.stripe_customer_id,
      metadata: OpenStruct.new(price_id: pack_10_price_id)
    )

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.success?, "expected success, got: #{result.error.inspect}"
    assert_equal 10, @user.credit_balance.reload.balance
  end

  test "grants 20 credits for the 20-pack price id" do
    pack_20_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 20 }[:stripe_price_id]

    session = OpenStruct.new(
      id: "cs_pack_20_#{SecureRandom.hex(4)}",
      customer: @user.stripe_customer_id,
      metadata: OpenStruct.new(price_id: pack_20_price_id)
    )

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.success?, "expected success, got: #{result.error.inspect}"
    assert_equal 20, @user.credit_balance.reload.balance
  end

  test "does not grant credits for an unknown price id" do
    session = OpenStruct.new(
      id: "cs_unknown_price_#{SecureRandom.hex(4)}",
      customer: @user.stripe_customer_id,
      metadata: OpenStruct.new(price_id: "price_totally_unrecognized")
    )

    before_balance = @user.credit_balance&.balance || 0

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.failure?, "expected failure for unknown price id"
    after_balance = @user.credit_balance&.reload&.balance || 0
    assert_equal before_balance, after_balance,
      "balance must not change when price id is unknown"
  end

  test "does not grant credits for a subscription price id" do
    session = OpenStruct.new(
      id: "cs_subscription_leak_#{SecureRandom.hex(4)}",
      customer: @user.stripe_customer_id,
      metadata: OpenStruct.new(price_id: AppConfig::Stripe::PRICE_ID_MONTHLY)
    )

    before_balance = @user.credit_balance&.balance || 0

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.failure?, "subscription price must not grant credits"
    after_balance = @user.credit_balance&.reload&.balance || 0
    assert_equal before_balance, after_balance
  end

  test "returns failure when no user found for customer" do
    pack_5_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 5 }[:stripe_price_id]

    session = OpenStruct.new(
      id: "cs_nobody",
      customer: "cus_nonexistent",
      metadata: OpenStruct.new(price_id: pack_5_price_id)
    )

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.failure?
    assert_equal "No user found for customer", result.error
  end
end
