# frozen_string_literal: true

require "test_helper"

class Mpp::GeneratesChallengeTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 150
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
      amount_cents: 150,
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

  test "method defaults to tempo when not specified (backwards compatibility)" do
    # Existing callers (Mpp::ProvisionsChallenge prior to k71e.1) call without
    # a method: kwarg. Default must remain tempo so the on-chain path is
    # unchanged.
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier
    )

    assert_equal "tempo", result.data[:method]
  end

  # ========================================================================
  # Stripe-method challenge issuance (agent-team-k71e.1)
  # ========================================================================
  #
  # PodRead must advertise a parallel method='stripe' challenge for SPT-paying
  # clients (e.g. @stripe/link-cli). Same HMAC machinery, different request
  # blob: networkId replaces recipient (SPTs are not chain-bound; networkId
  # is Stripe MPP's namespace discriminator).

  test "stripe method: returns a successful Result with challenge data" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    assert result.success?
    assert result.data.present?
  end

  test "stripe method: challenge[:method] is 'stripe'" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    assert_equal "stripe", result.data[:method]
  end

  test "stripe method: request blob includes amount, currency, networkId, voice_tier (mppx decode contract)" do
    # mppx 0.6.13's stripe decoder (link-cli decode.ts:75-98) requires
    # amount, currency, and methodDetails.networkId or networkId. Without
    # networkId mppx throws "Invalid stripe challenge request".
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    decoded = JSON.parse(Base64.decode64(result.data[:request]))
    assert decoded["amount"].present?, "stripe challenge request must include amount"
    assert decoded["currency"].present?, "stripe challenge request must include currency"
    assert decoded["networkId"].present?, "stripe challenge request must include networkId"
    assert_equal "premium", decoded["voice_tier"]
  end

  test "stripe method: amount is fiat cents as string (Stripe API convention)" do
    # Stripe MPP works in fiat cents, not on-chain base units. The amount
    # field in the stripe request blob is the same integer the merchant
    # passes to Stripe::PaymentIntent.create at verify time.
    result = Mpp::GeneratesChallenge.call(
      amount_cents: 150,
      currency: @currency,
      voice_tier: :premium,
      method: :stripe
    )

    decoded = JSON.parse(Base64.decode64(result.data[:request]))
    assert_equal "150", decoded["amount"]
    assert_equal @currency, decoded["currency"]
  end

  test "stripe method: networkId comes from AppConfig::Mpp::STRIPE_NETWORK_ID" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    decoded = JSON.parse(Base64.decode64(result.data[:request]))
    assert_equal AppConfig::Mpp::STRIPE_NETWORK_ID, decoded["networkId"]
  end

  test "stripe method: header_value advertises Payment scheme with method='stripe'" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    header = result.data[:header_value]
    assert header.start_with?("Payment ")
    assert_includes header, 'method="stripe"'
    assert_includes header, 'intent="charge"'
  end

  test "stripe method: HMAC id is deterministic and tier-bound" do
    freeze_time do
      standard = Mpp::GeneratesChallenge.call(
        amount_cents: 50, currency: @currency, voice_tier: :standard, method: :stripe
      )
      premium = Mpp::GeneratesChallenge.call(
        amount_cents: 50, currency: @currency, voice_tier: :premium, method: :stripe
      )

      assert_match(/\A[0-9a-f]{64}\z/, standard.data[:id])
      assert_not_equal standard.data[:id], premium.data[:id],
        "swapping voice_tier must invalidate the HMAC for stripe-method challenges too"
    end
  end

  test "stripe method: HMAC id differs from tempo-method id for the same inputs" do
    # Method is part of the HMAC pre-image, so a swapped method (e.g.
    # client claiming tempo when issuer signed stripe) must fail HMAC.
    freeze_time do
      tempo = Mpp::GeneratesChallenge.call(
        amount_cents: @amount_cents,
        currency: @currency,
        recipient: @recipient,
        voice_tier: @voice_tier,
        method: :tempo
      )
      stripe = Mpp::GeneratesChallenge.call(
        amount_cents: @amount_cents,
        currency: @currency,
        voice_tier: @voice_tier,
        method: :stripe
      )

      assert_not_equal tempo.data[:id], stripe.data[:id]
    end
  end

  test "stripe method: existing Mpp::VerifiesHmac validates the challenge unmodified" do
    # AC #4: VerifiesHmac handles both methods without modification.
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    challenge = {
      "id" => result.data[:id],
      "realm" => result.data[:realm],
      "method" => result.data[:method],
      "intent" => result.data[:intent],
      "request" => result.data[:request],
      "expires" => result.data[:expires]
    }

    hmac_result = Mpp::VerifiesHmac.call(challenge: challenge)
    assert hmac_result.success?, "VerifiesHmac must accept stripe-method challenges unchanged: #{hmac_result.error}"
  end

  test "stripe method: tampering with networkId in the request blob invalidates the HMAC" do
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: @voice_tier,
      method: :stripe
    )

    decoded = JSON.parse(Base64.decode64(result.data[:request]))
    decoded["networkId"] = "attacker_network"
    tampered_request = Base64.strict_encode64(JSON.generate(decoded))

    challenge = {
      "id" => result.data[:id],
      "realm" => result.data[:realm],
      "method" => result.data[:method],
      "intent" => result.data[:intent],
      "request" => tampered_request,
      "expires" => result.data[:expires]
    }

    hmac_result = Mpp::VerifiesHmac.call(challenge: challenge)
    refute hmac_result.success?
  end

  test "stripe method: recipient kwarg is ignored if passed (stripe is not chain-bound)" do
    # Defensive: a caller who passes recipient: alongside method: :stripe
    # should not see it leak into the challenge. Recipient is meaningless
    # for SPT — networkId is the namespace.
    result = Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @recipient,
      voice_tier: @voice_tier,
      method: :stripe
    )

    decoded = JSON.parse(Base64.decode64(result.data[:request]))
    assert_nil decoded["recipient"], "stripe challenge request must not include a recipient field"
  end
end
