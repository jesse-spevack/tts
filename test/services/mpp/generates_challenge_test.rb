# frozen_string_literal: true

require "test_helper"

class Mpp::GeneratesChallengeTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 100
    @currency = "usd"
    @recipient = "0x1234567890abcdef1234567890abcdef12345678"
    # agent-team-909 removed the :premium default — callers must pass tier
    # explicitly. Tests that don't care which tier use @voice_tier.
    @voice_tier = :premium
  end

  test "returns a successful Result with challenge data" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    assert result.success?
    assert result.data.present?
  end

  test "challenge includes id as HMAC-SHA256" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    challenge = result.data
    assert challenge[:id].present?
    # HMAC-SHA256 produces a 64-character hex string
    assert_match(/\A[0-9a-f]{64}\z/, challenge[:id])
  end

  test "challenge includes realm" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    challenge = result.data
    assert challenge[:realm].present?
  end

  test "challenge includes method set to tempo" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    challenge = result.data
    assert_equal "tempo", challenge[:method]
  end

  test "challenge includes intent set to charge" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    challenge = result.data
    assert_equal "charge", challenge[:intent]
  end

  test "challenge includes request as base64 JSON with amount currency and recipient" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    challenge = result.data
    assert challenge[:request].present?

    decoded = JSON.parse(Base64.decode64(challenge[:request]))
    # Amount is in token base units (string), not cents
    decimals = AppConfig::Mpp::TEMPO_TOKEN_DECIMALS
    expected_base_units = (@amount_cents * (10**decimals)) / 100
    assert_equal expected_base_units.to_s, decoded["amount"]
    # Currency is the token contract address, not fiat code
    assert_equal AppConfig::Mpp::TEMPO_CURRENCY_TOKEN, decoded["currency"]
    assert_equal @recipient, decoded["recipient"]
  end

  # Tier-aware challenges (agent-team-nkz.4)

  test "voice_tier is embedded in the request blob when passed explicitly" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: 50,
      currency: @currency,
      recipient: @recipient,
      voice_tier: :standard
    )

    decoded = JSON.parse(Base64.decode64(result.data[:request]))
    assert_equal "standard", decoded["voice_tier"]
    assert_equal :standard, result.data[:voice_tier]
  end

  test "voice_tier is required — omitting raises ArgumentError (agent-team-909)" do
    assert_raises(ArgumentError) do
      Mpp::GeneratesChallenge.call(
        amount_cents: @amount_cents,
        currency: @currency,
        recipient: @recipient
      )
    end
  end

  test "different voice_tiers yield different challenge ids (HMAC is tier-bound)" do
    freeze_time do
      standard = Mpp::GeneratesChallenge.call(
        amount_cents: 50, currency: @currency, recipient: @recipient, voice_tier: :standard
      )
      premium = Mpp::GeneratesChallenge.call(
        amount_cents: 50, currency: @currency, recipient: @recipient, voice_tier: :premium
      )

      assert_not_equal standard.data[:id], premium.data[:id],
        "swapping voice_tier must invalidate the HMAC so a Standard-priced challenge cannot be reused at Premium tier"
    end
  end

  test "challenge includes expires as ISO 8601 timestamp approximately 5 minutes from now" do
    freeze_time do
      result = Mpp::GeneratesChallenge.call(
        amount_cents: @amount_cents,
        currency: @currency,
        recipient: @recipient,
        voice_tier: @voice_tier
      )

      challenge = result.data
      expires = Time.iso8601(challenge[:expires])
      expected = 5.minutes.from_now

      assert_in_delta expected.to_i, expires.to_i, 5
    end
  end

  test "challenge id is deterministic given same inputs and secret" do
    result1 = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    result2 = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    assert_equal result1.data[:id], result2.data[:id]
  end

  test "challenge id changes when amount changes" do
    result1 = Mpp::GeneratesChallenge.call(
      amount_cents: 100,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    result2 = Mpp::GeneratesChallenge.call(
      amount_cents: 200,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    assert_not_equal result1.data[:id], result2.data[:id]
  end

  test "challenge id changes when recipient changes" do
    result1 = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: "0x1111111111111111111111111111111111111111",
      voice_tier: @voice_tier
    )

    result2 = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: "0x2222222222222222222222222222222222222222",
      voice_tier: @voice_tier
    )

    assert_not_equal result1.data[:id], result2.data[:id]
  end

  test "challenge can be serialized to a WWW-Authenticate header value" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    challenge = result.data

    # The challenge should support serialization to a WWW-Authenticate header
    # Expected format: Payment id="...", realm="...", method="tempo", intent="charge", request="...", expires="..."
    header_value = challenge[:header_value]
    assert header_value.present?
    assert header_value.start_with?("Payment ")
    assert_includes header_value, "id="
    assert_includes header_value, "realm="
    assert_includes header_value, 'method="tempo"'
    assert_includes header_value, 'intent="charge"'
    assert_includes header_value, "request="
    assert_includes header_value, "expires="
  end
end
