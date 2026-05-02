# frozen_string_literal: true

require "test_helper"

# Mirror of Mpp::FinalizesNarrationTest covering the bearer-authenticated
# Episode path. Same bug, same regression coverage — see that file for
# context. agent-team-k71e.6.
class Mpp::FinalizesEpisodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    @params = {
      source_type: "text",
      text: "Body of the article" * 10,
      title: "Headline"
    }
    @voice_override = nil

    # Don't drag in podcast / job plumbing — the finalizer's update_all
    # is what's under test, not CreatesEpisode's internals.
    @episode = episodes(:one)
    Mocktail.replace(::Mpp::CreatesEpisode)
    stubs { |m|
      ::Mpp::CreatesEpisode.call(user: m.any, params: m.any, voice_override: m.any)
    }.with { Result.success(@episode) }
  end

  test "stripe-scheme row: stripe_payment_intent_id is populated from the SPT redemption PI id" do
    spt_pi_id = "pi_spt_test_#{SecureRandom.hex(8)}"

    mpp_payment = MppPayment.create!(
      amount_cents: 150,
      currency: "usd",
      challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: nil,
      stripe_payment_intent_id: nil,
      status: :pending
    )

    result = Mpp::FinalizesEpisode.call(
      user: @user,
      mpp_payment: mpp_payment,
      tx_hash: spt_pi_id,
      params: @params,
      voice_override: @voice_override
    )

    assert result.success?, "FinalizesEpisode should succeed on a stripe-scheme row"
    assert_equal :winner, result.data[:outcome]

    mpp_payment.reload
    assert_equal "completed", mpp_payment.status
    assert_equal spt_pi_id, mpp_payment.tx_hash
    assert_equal spt_pi_id, mpp_payment.stripe_payment_intent_id,
      "Bug fix: stripe_payment_intent_id must also be populated from the SPT-redemption " \
      "PI id on stripe-scheme rows so Mpp::RefundsPayment can refund failures"
  end

  test "tempo-scheme row: stripe_payment_intent_id remains the deposit PI, not the on-chain tx_hash" do
    deposit_pi_id = "pi_deposit_#{SecureRandom.hex(8)}"
    on_chain_tx_hash = "0x#{SecureRandom.hex(32)}"

    mpp_payment = MppPayment.create!(
      amount_cents: 75,
      currency: "usd",
      challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: "0xdeposit#{SecureRandom.hex(16)}",
      stripe_payment_intent_id: deposit_pi_id,
      status: :pending
    )

    result = Mpp::FinalizesEpisode.call(
      user: @user,
      mpp_payment: mpp_payment,
      tx_hash: on_chain_tx_hash,
      params: @params,
      voice_override: @voice_override
    )

    assert result.success?
    mpp_payment.reload
    assert_equal on_chain_tx_hash, mpp_payment.tx_hash
    assert_equal deposit_pi_id, mpp_payment.stripe_payment_intent_id,
      "Tempo rows: the deposit-PI id must NOT be clobbered by the on-chain tx_hash"
  end
end
