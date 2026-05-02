# frozen_string_literal: true

require "test_helper"

# Regression coverage for agent-team-k71e.6 — the SPT refund bug.
#
# When a Stripe shared_payment_token (SPT) credential is redeemed, the
# Stripe PaymentIntent id Mpp::VerifiesSptCredential returns is the only
# handle Mpp::RefundsPayment can use to refund the customer. The finalizer
# is the last hop before that id is persisted; if it lands in tx_hash but
# not in stripe_payment_intent_id, RefundsPayment bails on its
# `stripe_payment_intent_id.blank?` guard and the customer's money is
# stranded (real $1.16 incident, 2026-05-02 — see bead notes).
#
# These tests pin the contract: after FinalizesNarration runs on an
# SPT-scheme MppPayment row, stripe_payment_intent_id MUST equal the
# SPT-redemption PI id passed in as tx_hash. They will go red on
# current main because the existing update_all only writes tx_hash.
class Mpp::FinalizesNarrationTest < ActiveSupport::TestCase
  setup do
    @params = {
      source_type: "text",
      text: "Body of the article" * 10,
      title: "Headline",
      voice: "felix"
    }
  end

  # The discriminator between tempo-scheme and stripe-scheme rows is
  # `deposit_address` — tempo rows have one (set by ProvisionsChallenge
  # from CreatesDepositAddress), stripe rows have nil. There is no
  # `scheme` enum on MppPayment; deposit_address.blank? is the only
  # column-level distinguisher available today. (Verified against
  # db/schema.rb mpp_payments columns, 2026-05-02.)
  test "stripe-scheme row: stripe_payment_intent_id is populated from the SPT redemption PI id" do
    spt_pi_id = "pi_spt_test_#{SecureRandom.hex(8)}"

    # Mimic what Mpp::ProvisionsChallenge persists for a stripe-method
    # challenge: pending row, no deposit_address, no
    # stripe_payment_intent_id (the SPT redemption hasn't happened yet).
    mpp_payment = MppPayment.create!(
      amount_cents: 150,
      currency: "usd",
      challenge_id: "chid_#{SecureRandom.hex(4)}",
      deposit_address: nil,
      stripe_payment_intent_id: nil,
      status: :pending
    )

    result = Mpp::FinalizesNarration.call(
      mpp_payment: mpp_payment,
      tx_hash: spt_pi_id,
      params: @params
    )

    assert result.success?, "FinalizesNarration should succeed on a stripe-scheme row"
    assert_equal :winner, result.data[:outcome]

    mpp_payment.reload
    assert_equal "completed", mpp_payment.status
    assert_equal spt_pi_id, mpp_payment.tx_hash,
      "Existing behavior: tx_hash carries the SPT-redemption PI id"
    assert_equal spt_pi_id, mpp_payment.stripe_payment_intent_id,
      "Bug fix: stripe_payment_intent_id must also be populated from the SPT-redemption " \
      "PI id on stripe-scheme rows so Mpp::RefundsPayment can refund failures"
  end

  # Tempo rows MUST be unaffected by the fix — ProvisionsChallenge has
  # already set stripe_payment_intent_id to the deposit-PI on tempo rows,
  # and that value must NOT be overwritten by the on-chain tx_hash.
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

    result = Mpp::FinalizesNarration.call(
      mpp_payment: mpp_payment,
      tx_hash: on_chain_tx_hash,
      params: @params
    )

    assert result.success?
    mpp_payment.reload
    assert_equal on_chain_tx_hash, mpp_payment.tx_hash
    assert_equal deposit_pi_id, mpp_payment.stripe_payment_intent_id,
      "Tempo rows: the deposit-PI id must NOT be clobbered by the on-chain tx_hash"
  end
end
