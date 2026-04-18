# frozen_string_literal: true

require "test_helper"

class Mpp::ProvisionsChallengeTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 100
    @currency = "usd"
    @deposit_address = "0x1234567890abcdef1234567890abcdef12345678"
    @payment_intent_id = "pi_test_abc123"

    Mocktail.replace(Mpp::CreatesDepositAddress)
    stubs { |_m| Mpp::CreatesDepositAddress.call(amount_cents: @amount_cents, currency: @currency) }
      .with { Result.success(deposit_address: @deposit_address, payment_intent_id: @payment_intent_id) }
  end

  test "returns Provisioned value with challenge and deposit_address on success" do
    result = Mpp::ProvisionsChallenge.call(amount_cents: @amount_cents, currency: @currency)

    assert result.success?
    assert_kind_of Mpp::ProvisionsChallenge::Provisioned, result.data
    assert_equal @deposit_address, result.data.deposit_address
    assert result.data.challenge[:id].present?
  end

  test "signs challenge with the provisioned deposit_address as recipient" do
    result = Mpp::ProvisionsChallenge.call(amount_cents: @amount_cents, currency: @currency)

    request_json = Base64.decode64(result.data.challenge[:request])
    request = JSON.parse(request_json)
    assert_equal @deposit_address, request["recipient"]
  end

  test "persists a pending MppPayment linking challenge_id, deposit_address, payment_intent_id" do
    assert_difference -> { MppPayment.count }, 1 do
      Mpp::ProvisionsChallenge.call(amount_cents: @amount_cents, currency: @currency)
    end

    payment = MppPayment.order(:created_at).last
    assert_equal "pending", payment.status
    assert_equal @deposit_address, payment.deposit_address
    assert_equal @payment_intent_id, payment.stripe_payment_intent_id
    assert_equal @amount_cents, payment.amount_cents
    assert_equal @currency, payment.currency
  end

  test "returns the deposit failure result when provisioning fails" do
    stubs { |_m| Mpp::CreatesDepositAddress.call(amount_cents: @amount_cents, currency: @currency) }
      .with { Result.failure("Stripe down") }

    assert_no_difference -> { MppPayment.count } do
      result = Mpp::ProvisionsChallenge.call(amount_cents: @amount_cents, currency: @currency)
      refute result.success?
      assert_equal "Stripe down", result.error
    end
  end
end
