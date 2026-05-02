# frozen_string_literal: true

module Mpp
  # Provisions a 402 challenge: allocates a Tempo deposit address and
  # signs parallel tempo + stripe challenges against a shared price and
  # expiry. Persists one pending MppPayment row per challenge_id (one
  # per method, since challenge_id is method-bound via HMAC); the unused
  # row is swept by CleanupStaleMppPaymentsJob after CHALLENGE_TTL_SECONDS.
  class ProvisionsChallenge
    Provisioned = Data.define(:tempo_challenge, :stripe_challenge, :deposit_address)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(amount_cents:, currency:, voice_tier:)
      @amount_cents = amount_cents
      @currency = currency
      @voice_tier = voice_tier
    end

    def call
      # Provision the deposit address first so the Tempo challenge can
      # bind to it; both challenges share amount, expiry, and voice_tier.
      deposit_result = Mpp::CreatesDepositAddress.call(
        amount_cents: amount_cents,
        currency: currency
      )
      return deposit_result unless deposit_result.success?

      deposit_address = deposit_result.data[:deposit_address]
      payment_intent_id = deposit_result.data[:payment_intent_id]

      tempo_challenge = Mpp::GeneratesChallenge.call(
        amount_cents: amount_cents,
        currency: currency,
        recipient: deposit_address,
        voice_tier: voice_tier,
        method: :tempo
      ).data

      stripe_challenge = Mpp::GeneratesChallenge.call(
        amount_cents: amount_cents,
        currency: currency,
        voice_tier: voice_tier,
        method: :stripe
      ).data

      # The stripe row's stripe_payment_intent_id is populated by
      # VerifiesSptCredential at verify time.
      MppPayment.create!(
        amount_cents: amount_cents,
        currency: currency,
        challenge_id: tempo_challenge[:id],
        deposit_address: deposit_address,
        stripe_payment_intent_id: payment_intent_id,
        status: :pending
      )

      MppPayment.create!(
        amount_cents: amount_cents,
        currency: currency,
        challenge_id: stripe_challenge[:id],
        status: :pending
      )

      Result.success(
        Provisioned.new(
          tempo_challenge: tempo_challenge,
          stripe_challenge: stripe_challenge,
          deposit_address: deposit_address
        )
      )
    end

    private

    attr_reader :amount_cents, :currency, :voice_tier
  end
end
