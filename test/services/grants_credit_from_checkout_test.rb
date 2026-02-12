# frozen_string_literal: true

require "test_helper"
require "ostruct"

class GrantsCreditFromCheckoutTest < ActiveSupport::TestCase
  test "grants credits to user matching stripe customer" do
    user = users(:subscriber)

    session = OpenStruct.new(
      id: "cs_credit_checkout",
      customer: user.stripe_customer_id
    )

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.success?
    assert_equal AppConfig::Credits::PACK_SIZE, user.credit_balance.reload.balance
  end

  test "returns failure when no user found for customer" do
    session = OpenStruct.new(
      id: "cs_unknown",
      customer: "cus_nonexistent"
    )

    result = GrantsCreditFromCheckout.call(session: session)

    assert result.failure?
    assert_equal "No user found for customer", result.error
  end
end
