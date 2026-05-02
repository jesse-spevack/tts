# frozen_string_literal: true

require "test_helper"

# Focused dispatcher-level tests for Mpp::VerifiesCredential. The full
# tempo on-chain coverage stays in verifies_credential_test.rb (regression
# guarantee for the pre-dispatcher behavior); this file proves the
# method-based routing in #call.
class Mpp::VerifiesCredentialDispatcherTest < ActiveSupport::TestCase
  setup do
    @amount_cents = AppConfig::Mpp::PRICE_STANDARD_CENTS
    @currency = AppConfig::Mpp::CURRENCY
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"
    Stripe.api_key = "sk_test_fake"
  end

  test "method=stripe routes to Mpp::VerifiesSptCredential" do
    challenge = stripe_challenge
    persist_pending_payment(challenge: challenge)

    Mocktail.replace(Mpp::VerifiesSptCredential)
    expected = Result.success(
      tx_hash: "pi_test_routed",
      stripe_payment_intent_id: "pi_test_routed",
      challenge_id: challenge[:id],
      voice_tier: :standard
    )
    stubs do |m|
      Mpp::VerifiesSptCredential.call(
        challenge: m.is_a(Hash),
        payload: m.is_a(Hash),
        mpp_payment: m.is_a(MppPayment)
      )
    end.with { expected }

    credential = build_credential(challenge: challenge, payload: { spt: "spt_test_x" })

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.success?
    assert_equal "pi_test_routed", result.data[:tx_hash]
  end

  test "method=tempo routes to Mpp::VerifiesTempoCredential (no stripe call)" do
    challenge = tempo_challenge
    persist_pending_tempo_payment(challenge: challenge)

    Mocktail.replace(Mpp::VerifiesTempoCredential)
    Mocktail.replace(Mpp::VerifiesSptCredential)
    expected = Result.success(
      tx_hash: "0xtempo_test",
      amount: "750000",
      recipient: @deposit_address,
      challenge_id: challenge[:id],
      voice_tier: :standard
    )
    stubs do |m|
      Mpp::VerifiesTempoCredential.call(
        challenge: m.is_a(Hash),
        payload: m.is_a(Hash),
        mpp_payment: m.is_a(MppPayment)
      )
    end.with { expected }

    credential = build_credential(
      challenge: challenge,
      payload: { type: "hash", hash: "0xfeed" }
    )

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.success?
    assert_equal "0xtempo_test", result.data[:tx_hash]

    # Sanity: the SPT verifier should NEVER be reached on a tempo credential.
    assert_raises(Mocktail::VerificationError) do
      verify do |m|
        Mpp::VerifiesSptCredential.call(
          challenge: m.is_a(Hash),
          payload: m.is_a(Hash),
          mpp_payment: m.is_a(MppPayment)
        )
      end
    end
  end

  test "unknown method returns descriptive failure" do
    # Forge a credential whose challenge advertises an unsupported method.
    # The HMAC has to cover that method or we'd fail upstream — recompute
    # by hand so we land on the dispatcher's else branch, not on HMAC fail.
    realm = AppConfig::Domain::HOST
    method_str = "lightning"
    intent = "charge"
    request_blob = { amount: @amount_cents.to_s, currency: @currency, voice_tier: "standard" }
    request_json = JSON.generate(request_blob)
    request_b64 = Base64.strict_encode64(request_json)
    expires = (Time.current + 300).iso8601
    hmac_data = "#{realm}|#{method_str}|#{intent}|#{request_json}|#{expires}"
    id = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, hmac_data)

    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: id,
      status: :pending
    )

    credential_hash = {
      challenge: {
        id: id,
        realm: realm,
        method: method_str,
        intent: intent,
        request: request_b64,
        expires: expires
      },
      payload: { foo: "bar" }
    }
    credential = Base64.strict_encode64(JSON.generate(credential_hash))

    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/Unsupported credential method: lightning/, result.error)
  end

  test "shared upstream gates run before dispatch — expired stripe credential fails on expiry, not in SPT verifier" do
    # If the dispatcher mistakenly delegated before the expiry check, an
    # expired SPT credential would hit Stripe and waste a charge attempt.
    # Verify the order: expiry first, dispatch second.
    Mocktail.replace(Mpp::VerifiesSptCredential)

    expired_challenge = nil
    travel_to(10.minutes.ago) do
      expired_challenge = stripe_challenge
    end
    persist_pending_payment(challenge: expired_challenge)

    credential = build_credential(challenge: expired_challenge, payload: { spt: "spt_should_never_redeem" })
    result = Mpp::VerifiesCredential.call(credential: credential)

    assert result.failure?
    assert_match(/expired/i, result.error)

    # Mocktail records ALL invocations of the replaced module — if we never
    # called the SPT verifier, no recorded calls should exist. Verify with
    # `times(0)` semantics by attempting to verify any call.
    assert_raises(Mocktail::VerificationError) do
      verify do |m|
        Mpp::VerifiesSptCredential.call(
          challenge: m.any,
          payload: m.any,
          mpp_payment: m.any
        )
      end
    end
  end

  private

  def stripe_challenge
    Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      voice_tier: :standard,
      method: :stripe
    ).data
  end

  def tempo_challenge
    Mpp::GeneratesChallenge.call(
      amount_cents: @amount_cents,
      currency: @currency,
      recipient: @deposit_address,
      voice_tier: :standard,
      method: :tempo
    ).data
  end

  def persist_pending_payment(challenge:)
    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: challenge[:id],
      status: :pending
    )
  end

  def persist_pending_tempo_payment(challenge:)
    MppPayment.create!(
      amount_cents: @amount_cents,
      currency: @currency,
      challenge_id: challenge[:id],
      deposit_address: @deposit_address,
      stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(4)}",
      status: :pending
    )
  end

  def build_credential(challenge:, payload:)
    credential_hash = {
      challenge: {
        id: challenge[:id],
        realm: challenge[:realm],
        method: challenge[:method],
        intent: challenge[:intent],
        request: challenge[:request],
        expires: challenge[:expires]
      },
      payload: payload
    }
    Base64.strict_encode64(JSON.generate(credential_hash))
  end
end
