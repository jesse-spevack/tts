# frozen_string_literal: true

require "test_helper"

class Mpp::ProvisionsChallengeTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 100
    @currency = "usd"
    @deposit_address = "0x1234567890abcdef1234567890abcdef12345678"
    @payment_intent_id = "pi_test_abc123"
    # agent-team-909 removed the :premium default on ProvisionsChallenge.
    # Tests that don't care which tier use @voice_tier.
    @voice_tier = :premium

    Mocktail.replace(Mpp::CreatesDepositAddress)
    stubs { |_m| Mpp::CreatesDepositAddress.call(amount_cents: @amount_cents, currency: @currency) }
      .with { Result.success(deposit_address: @deposit_address, payment_intent_id: @payment_intent_id) }
  end

  test "returns Provisioned with tempo_challenge, stripe_challenge, and deposit_address on success" do
    result = Mpp::ProvisionsChallenge.call(
      amount_cents: @amount_cents, currency: @currency, voice_tier: @voice_tier
    )

    assert result.success?
    assert_kind_of Mpp::ProvisionsChallenge::Provisioned, result.data
    assert_equal @deposit_address, result.data.deposit_address
    assert result.data.tempo_challenge[:id].present?
    assert result.data.stripe_challenge[:id].present?
    assert_equal "tempo", result.data.tempo_challenge[:method]
    assert_equal "stripe", result.data.stripe_challenge[:method]
    assert_not_equal result.data.tempo_challenge[:id],
      result.data.stripe_challenge[:id],
      "tempo and stripe challenges must have distinct HMAC ids — method is in the pre-image"
  end

  test "signs the tempo challenge with the provisioned deposit_address as recipient" do
    result = Mpp::ProvisionsChallenge.call(
      amount_cents: @amount_cents, currency: @currency, voice_tier: @voice_tier
    )

    request = JSON.parse(Base64.decode64(result.data.tempo_challenge[:request]))
    assert_equal @deposit_address, request["recipient"]
  end

  test "stripe challenge request blob includes networkId and fiat-cents amount" do
    # mppx 0.6.13 stripe decoder requires networkId; without it the client
    # throws before retrying. Fiat cents (not on-chain base units) match
    # what the merchant will pass to Stripe::PaymentIntent.create at
    # verify time (k71e.5).
    result = Mpp::ProvisionsChallenge.call(
      amount_cents: @amount_cents, currency: @currency, voice_tier: @voice_tier
    )

    request = JSON.parse(Base64.decode64(result.data.stripe_challenge[:request]))
    assert_equal @amount_cents.to_s, request["amount"]
    assert_equal @currency, request["currency"]
    assert_equal AppConfig::Mpp::STRIPE_NETWORK_ID, request["networkId"]
  end

  test "persists two pending MppPayment rows — one per challenge_id" do
    assert_difference -> { MppPayment.count }, 2 do
      Mpp::ProvisionsChallenge.call(
        amount_cents: @amount_cents, currency: @currency, voice_tier: @voice_tier
      )
    end

    rows = MppPayment.order(:created_at).last(2)
    rows.each do |row|
      assert_equal "pending", row.status
      assert_equal @amount_cents, row.amount_cents
      assert_equal @currency, row.currency
    end
  end

  test "tempo MppPayment row carries deposit_address and the deposit-PI; stripe row carries neither" do
    result = Mpp::ProvisionsChallenge.call(
      amount_cents: @amount_cents, currency: @currency, voice_tier: @voice_tier
    )

    tempo_row = MppPayment.find_by!(challenge_id: result.data.tempo_challenge[:id])
    stripe_row = MppPayment.find_by!(challenge_id: result.data.stripe_challenge[:id])

    assert_equal @deposit_address, tempo_row.deposit_address
    assert_equal @payment_intent_id, tempo_row.stripe_payment_intent_id

    assert_nil stripe_row.deposit_address
    # Mpp::VerifiesSptCredential (k71e.5) populates stripe_payment_intent_id
    # at verify time with the SPT-redemption PI. At challenge time it stays
    # nil so accounting can tell tempo and stripe rows apart.
    assert_nil stripe_row.stripe_payment_intent_id
  end

  test "returns the deposit failure result when provisioning fails" do
    stubs { |_m| Mpp::CreatesDepositAddress.call(amount_cents: @amount_cents, currency: @currency) }
      .with { Result.failure("Stripe down") }

    assert_no_difference -> { MppPayment.count } do
      result = Mpp::ProvisionsChallenge.call(
        amount_cents: @amount_cents, currency: @currency, voice_tier: @voice_tier
      )
      refute result.success?
      assert_equal "Stripe down", result.error
    end
  end

  test "voice_tier is required — omitting raises ArgumentError (agent-team-909)" do
    assert_raises(ArgumentError) do
      Mpp::ProvisionsChallenge.call(amount_cents: @amount_cents, currency: @currency)
    end
  end
end
