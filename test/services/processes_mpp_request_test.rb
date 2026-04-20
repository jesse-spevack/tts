# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Focused unit tests for ProcessesMppRequest's orchestration logic. The
# end-to-end flow (credential verification, Stripe/Tempo RPC, finalizer
# races) is covered comprehensively in:
#
#   test/controllers/api/v1/mpp/narrations_controller_test.rb
#   test/controllers/api/v1/mpp/episodes_controller_test.rb
#
# These tests pin the Outcome contract the controller's render_mpp_result
# relies on — each outcome symbol maps 1:1 to an HTTP response.
class ProcessesMppRequestTest < ActiveSupport::TestCase
  FakeRequest = Struct.new(:headers)

  setup do
    Stripe.api_key = "sk_test_fake"
    @user = users(:free_user)
    @valid_params = {
      title: "Test",
      author: "Author",
      description: "Desc",
      content: "Content " * 50,
      url: "https://example.com/a",
      source_type: "url"
    }
  end

  def build_request(auth_header: nil)
    FakeRequest.new(auth_header ? { "Authorization" => auth_header } : {})
  end

  # =======================================================================
  # :invalid_voice — bogus voice_id
  # =======================================================================

  test "invalid voice returns :invalid_voice outcome with error message" do
    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "totally_made_up_voice"),
      request: build_request
    )

    assert result.success?
    assert_equal :invalid_voice, result.data.outcome
    assert_match(/totally_made_up_voice/, result.data.error)
  end

  test "invalid voice does not invoke the finalizer" do
    Mocktail.replace(::Mpp::FinalizesNarration)

    ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "nope"),
      request: build_request
    )

    assert_equal 0, Mocktail.calls(::Mpp::FinalizesNarration, :call).size
  end

  # =======================================================================
  # :challenge_issued — no credential → 402 (fresh challenge)
  # =======================================================================

  test "no Payment credential returns :challenge_issued" do
    stub_stripe_deposit_address
    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "felix"),
      request: build_request
    )

    assert result.success?
    assert_equal :challenge_issued, result.data.outcome
    assert_not_nil result.data.challenge
    assert_not_nil result.data.deposit_address
    assert_equal AppConfig::Mpp::PRICE_STANDARD_CENTS, result.data.amount_cents
    assert_equal :standard, result.data.voice_tier
  end

  test "no credential, premium voice returns challenge at Premium price" do
    stub_stripe_deposit_address
    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesEpisode,
      user: @user,
      params: @valid_params.merge(voice: "callum"),
      request: build_request
    )

    assert_equal :challenge_issued, result.data.outcome
    assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, result.data.amount_cents
    assert_equal :premium, result.data.voice_tier
  end

  # =======================================================================
  # :challenge_issued — malformed credential → re-challenge
  # =======================================================================

  test "malformed Payment credential returns :challenge_issued (re-challenge)" do
    stub_stripe_deposit_address
    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params,
      request: build_request(auth_header: "Payment not_a_valid_credential")
    )

    assert_equal :challenge_issued, result.data.outcome
  end

  # =======================================================================
  # :challenge_provisioning_failed — ProvisionsChallenge failed
  # =======================================================================

  test "ProvisionsChallenge failure returns :challenge_provisioning_failed" do
    Mocktail.replace(::Mpp::ProvisionsChallenge)
    stubs { |m| ::Mpp::ProvisionsChallenge.call(amount_cents: m.any, currency: m.any, voice_tier: m.any) }
      .with { Result.failure("stripe_down") }

    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params,
      request: build_request
    )

    assert_equal :challenge_provisioning_failed, result.data.outcome
    assert_equal "stripe_down", result.data.error
  end

  # =======================================================================
  # :created — winner path (narration)
  # =======================================================================

  test "narration winner returns :created with record and receipt_header" do
    mpp_payment = MppPayment.create!(
      amount_cents: 75, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_x", status: :pending
    )
    narration = narrations(:one)

    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :standard)
    Mocktail.replace(::Mpp::FinalizesNarration)
    stubs { |m| ::Mpp::FinalizesNarration.call(mpp_payment: m.any, tx_hash: m.any, params: m.any) }
      .with { Result.success(narration: narration, outcome: :winner) }

    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "felix"),
      request: build_request(auth_header: "Payment stub")
    )

    assert_equal :created, result.data.outcome
    assert_equal narration, result.data.record
    assert_not_nil result.data.receipt_header
  end

  # =======================================================================
  # :created — idempotent loser (narration)
  # =======================================================================

  test "narration loser with record returns :created (idempotent retry)" do
    mpp_payment = MppPayment.create!(
      amount_cents: 75, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_y", status: :pending
    )
    narration = narrations(:one)

    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :standard)
    Mocktail.replace(::Mpp::FinalizesNarration)
    stubs { |m| ::Mpp::FinalizesNarration.call(mpp_payment: m.any, tx_hash: m.any, params: m.any) }
      .with { Result.success(narration: narration, outcome: :loser) }

    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "felix"),
      request: build_request(auth_header: "Payment stub")
    )

    assert_equal :created, result.data.outcome
    assert_equal narration, result.data.record
  end

  # =======================================================================
  # :loser_conflict — episode loser with nil record → 409
  # =======================================================================

  test "episode loser with nil record returns :loser_conflict" do
    mpp_payment = MppPayment.create!(
      amount_cents: 100, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_z", status: :pending
    )

    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :premium)
    Mocktail.replace(::Mpp::FinalizesEpisode)
    stubs { |m|
      ::Mpp::FinalizesEpisode.call(user: m.any, mpp_payment: m.any, tx_hash: m.any, params: m.any, voice_override: m.any)
    }.with { Result.success(episode: nil, outcome: :loser) }

    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesEpisode,
      user: @user,
      params: @valid_params.merge(voice: "callum"),
      request: build_request(auth_header: "Payment stub")
    )

    assert_equal :loser_conflict, result.data.outcome
    assert_nil result.data.record
  end

  # =======================================================================
  # :creation_failed — finalizer returned failure
  # =======================================================================

  test "finalizer failure returns :creation_failed with error" do
    mpp_payment = MppPayment.create!(
      amount_cents: 75, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_fail", status: :pending
    )

    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :standard)
    Mocktail.replace(::Mpp::FinalizesNarration)
    stubs { |m| ::Mpp::FinalizesNarration.call(mpp_payment: m.any, tx_hash: m.any, params: m.any) }
      .with { Result.failure("boom") }

    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "felix"),
      request: build_request(auth_header: "Payment stub")
    )

    assert_equal :creation_failed, result.data.outcome
    assert_equal "boom", result.data.error
  end

  # =======================================================================
  # :challenge_issued — tier mismatch
  # =======================================================================

  test "tier mismatch (Standard credential for Premium voice) returns :challenge_issued" do
    stub_stripe_deposit_address
    mpp_payment = MppPayment.create!(
      amount_cents: 75, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_tier", status: :pending
    )

    # Credential is Standard-tier but caller requests a Premium voice.
    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :standard)

    result = ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "callum"), # premium
      request: build_request(auth_header: "Payment stub")
    )

    assert_equal :challenge_issued, result.data.outcome
    # Re-challenge is at the REQUESTED voice's price, not the credential's
    assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, result.data.amount_cents
    assert_equal :premium, result.data.voice_tier
  end

  # =======================================================================
  # Anonymous vs authenticated wiring
  # =======================================================================

  test "finalizer receives nil user for narration flow (no :user kwarg)" do
    mpp_payment = MppPayment.create!(
      amount_cents: 75, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_n", status: :pending
    )
    narration = narrations(:one)

    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :standard)
    Mocktail.replace(::Mpp::FinalizesNarration)
    stubs { |m| ::Mpp::FinalizesNarration.call(mpp_payment: m.any, tx_hash: m.any, params: m.any) }
      .with { Result.success(narration: narration, outcome: :winner) }

    ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesNarration,
      user: nil,
      params: @valid_params.merge(voice: "felix"),
      request: build_request(auth_header: "Payment stub")
    )

    # Narration finalizer signature does not include :user — if the service
    # passed :user the Mocktail stub above would not match and we'd get a
    # failure instead of :created.
    call = Mocktail.calls(::Mpp::FinalizesNarration, :call).first
    assert call, "Expected FinalizesNarration to be called once"
    assert_not call.kwargs.key?(:user), "Narration finalizer must not be called with :user"
    assert call.kwargs.key?(:mpp_payment)
    assert call.kwargs.key?(:tx_hash)
    assert call.kwargs.key?(:params)
  end

  test "finalizer receives user and voice_override as google voice for episode flow" do
    mpp_payment = MppPayment.create!(
      amount_cents: 100, currency: "usd", challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xaddr", stripe_payment_intent_id: "pi_e", status: :pending
    )

    stub_verification_ok(challenge_id: mpp_payment.challenge_id, voice_tier: :premium)
    Mocktail.replace(::Mpp::FinalizesEpisode)
    stubs { |m|
      ::Mpp::FinalizesEpisode.call(user: m.any, mpp_payment: m.any, tx_hash: m.any, params: m.any, voice_override: m.any)
    }.with { Result.success(episode: OpenStruct.new(prefix_id: "ep_fake"), outcome: :winner) }

    ProcessesMppRequest.call(
      finalizer: ::Mpp::FinalizesEpisode,
      user: @user,
      params: @valid_params.merge(voice: "callum"),
      request: build_request(auth_header: "Payment stub")
    )

    call = Mocktail.calls(::Mpp::FinalizesEpisode, :call).first
    assert call, "Expected FinalizesEpisode to be called once"
    assert_equal @user, call.kwargs[:user]
    assert_equal "en-GB-Chirp3-HD-Enceladus", call.kwargs[:voice_override],
      "Episode finalizer must receive the Premium google voice for callum"
  end

  # =======================================================================
  # Helpers
  # =======================================================================

  private

  # Stub ::Mpp::VerifiesCredential.call to return a successful verification
  # for the given challenge_id / voice_tier.
  def stub_verification_ok(challenge_id:, voice_tier:, tx_hash: "0x#{SecureRandom.hex(32)}")
    Mocktail.replace(::Mpp::VerifiesCredential)
    stubs { |m| ::Mpp::VerifiesCredential.call(credential: m.any) }.with {
      Result.success(
        tx_hash: tx_hash,
        amount: 100,
        recipient: "0xaddr",
        challenge_id: challenge_id,
        voice_tier: voice_tier
      )
    }
  end

  def stub_stripe_deposit_address(address: "0xdepXYZ")
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_#{SecureRandom.hex(8)}",
        object: "payment_intent",
        amount: AppConfig::Mpp::PRICE_PREMIUM_CENTS,
        currency: "usd",
        status: "requires_action",
        next_action: {
          type: "crypto_display_details",
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: address }
            }
          }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })
  end
end
