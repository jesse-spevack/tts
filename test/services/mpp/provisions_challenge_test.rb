# frozen_string_literal: true

require "test_helper"

class Mpp::ProvisionsChallengeTest < ActiveSupport::TestCase
  setup do
    @tempo_amount_cents = 200
    @stripe_amount_cents = 250
    @currency = "usd"
    @deposit_address = "0x1234567890abcdef1234567890abcdef12345678"
    @payment_intent_id = "pi_test_abc123"
    @voice_tier = :premium

    Mocktail.replace(Mpp::CreatesDepositAddress)
    stubs { |_m| Mpp::CreatesDepositAddress.call(amount_cents: @tempo_amount_cents, currency: @currency) }
      .with { Result.success(deposit_address: @deposit_address, payment_intent_id: @payment_intent_id) }
  end

  def call_provision(**overrides)
    Mpp::ProvisionsChallenge.call(
      tempo_amount_cents: @tempo_amount_cents,
      stripe_amount_cents: @stripe_amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      **overrides
    )
  end

  test "returns Provisioned with tempo_challenge, stripe_challenge, and deposit_address on success" do
    result = call_provision

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
    result = call_provision

    request = JSON.parse(Base64.decode64(result.data.tempo_challenge[:request]))
    assert_equal @deposit_address, request["recipient"]
  end

  test "stripe challenge request blob includes networkId and fiat-cents amount" do
    result = call_provision

    request = JSON.parse(Base64.decode64(result.data.stripe_challenge[:request]))
    assert_equal @stripe_amount_cents.to_s, request["amount"]
    assert_equal @currency, request["currency"]
    assert_equal AppConfig::Mpp::STRIPE_NETWORK_ID, request["networkId"]
  end

  test "tempo and stripe challenge request blobs carry their own per-scheme amount (evo5)" do
    result = call_provision

    tempo_decoded = JSON.parse(Base64.decode64(result.data.tempo_challenge[:request]))
    stripe_decoded = JSON.parse(Base64.decode64(result.data.stripe_challenge[:request]))

    decimals = AppConfig::Mpp::TEMPO_TOKEN_DECIMALS
    expected_tempo_base_units = (@tempo_amount_cents * (10**decimals)) / 100
    assert_equal expected_tempo_base_units.to_s, tempo_decoded["amount"]
    assert_equal @stripe_amount_cents.to_s, stripe_decoded["amount"]
  end

  test "persists two pending MppPayment rows at their per-scheme amounts (evo5)" do
    assert_difference -> { MppPayment.count }, 2 do
      call_provision
    end

    result = call_provision
    tempo_row = MppPayment.find_by!(challenge_id: result.data.tempo_challenge[:id])
    stripe_row = MppPayment.find_by!(challenge_id: result.data.stripe_challenge[:id])

    assert_equal "pending", tempo_row.status
    assert_equal "pending", stripe_row.status
    assert_equal @tempo_amount_cents, tempo_row.amount_cents
    assert_equal @stripe_amount_cents, stripe_row.amount_cents
    assert_equal @currency, tempo_row.currency
    assert_equal @currency, stripe_row.currency
  end

  test "tempo MppPayment row carries deposit_address and the deposit-PI; stripe row carries neither" do
    result = call_provision

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
    stubs { |_m| Mpp::CreatesDepositAddress.call(amount_cents: @tempo_amount_cents, currency: @currency) }
      .with { Result.failure("Stripe down") }

    assert_no_difference -> { MppPayment.count } do
      result = call_provision
      refute result.success?
      assert_equal "Stripe down", result.error
    end
  end

  test "voice_tier is required — omitting raises ArgumentError" do
    assert_raises(ArgumentError) do
      Mpp::ProvisionsChallenge.call(
        tempo_amount_cents: @tempo_amount_cents,
        stripe_amount_cents: @stripe_amount_cents,
        currency: @currency
      )
    end
  end
end
