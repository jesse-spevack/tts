# frozen_string_literal: true

module Mpp
  # Provisions a 402 Payment Required challenge: allocates a Stripe
  # PaymentIntent with a crypto deposit address, HMAC-signs the
  # challenge against that address, and persists a pending MppPayment
  # row that binds challenge_id ↔ deposit_address ↔ payment_intent_id.
  #
  # Returns Result.success(Provisioned) on success. Controller owns
  # the response rendering (WWW-Authenticate header + 402 JSON body);
  # this service owns the business logic.
  class ProvisionsChallenge
    Provisioned = Data.define(:challenge, :deposit_address)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:)
      @amount_cents = amount_cents
      @currency = currency
    end

    def call
      # Step 1: provision the Stripe PaymentIntent + deposit address
      # FIRST so the real on-chain recipient is known before we sign.
      deposit_result = Mpp::CreatesDepositAddress.call(
        amount_cents: amount_cents,
        currency: currency
      )
      return deposit_result unless deposit_result.success?

      deposit_address = deposit_result.data[:deposit_address]
      payment_intent_id = deposit_result.data[:payment_intent_id]

      # Step 2: sign the HMAC challenge with the real deposit_address
      # as recipient. Binds the on-chain destination into the HMAC so
      # it cannot be swapped at verification time.
      challenge_result = Mpp::GeneratesChallenge.call(
        amount_cents: amount_cents,
        currency: currency,
        recipient: deposit_address
      )
      challenge = challenge_result.data

      # Step 3: persist a pending MppPayment linking challenge_id to
      # the deposit_address and stripe_payment_intent_id.
      # VerifiesCredential resolves deposit_address from this row (not
      # client payload) at verification time; refund accounting uses
      # stripe_payment_intent_id.
      MppPayment.create!(
        amount_cents: amount_cents,
        currency: currency,
        challenge_id: challenge[:id],
        deposit_address: deposit_address,
        stripe_payment_intent_id: payment_intent_id,
        status: :pending
      )

      Result.success(Provisioned.new(challenge: challenge, deposit_address: deposit_address))
    end

    private

    attr_reader :amount_cents, :currency
  end
end
