# frozen_string_literal: true

module Mpp
  # Provisions a 402 challenge: allocates a Tempo deposit address and
  # signs parallel tempo + stripe challenges, each at its own per-scheme
  # price. Persists one pending MppPayment row per challenge_id (one per
  # method) at the matching scheme's amount; the unused row is swept by
  # CleanupStaleMppPaymentsJob after CHALLENGE_TTL_SECONDS.
  class ProvisionsChallenge
    Provisioned = Data.define(:tempo_challenge, :stripe_challenge, :deposit_address)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(tempo_amount_cents:, stripe_amount_cents:, currency:, voice_tier:)
      @tempo_amount_cents = tempo_amount_cents
      @stripe_amount_cents = stripe_amount_cents
      @currency = currency
      @voice_tier = voice_tier
    end

    def call
      # The deposit-address PI charges in fiat cents and lives on the
      # tempo-method side, so it gets the tempo amount.
      deposit_result = Mpp::CreatesDepositAddress.call(
        amount_cents: tempo_amount_cents,
        currency: currency
      )
      return deposit_result unless deposit_result.success?

      deposit_address = deposit_result.data[:deposit_address]
      payment_intent_id = deposit_result.data[:payment_intent_id]

      tempo_challenge = Mpp::GeneratesChallenge.call(
        amount_cents: tempo_amount_cents,
        currency: currency,
        recipient: deposit_address,
        voice_tier: voice_tier,
        method: :tempo
      ).data

      stripe_challenge = Mpp::GeneratesChallenge.call(
        amount_cents: stripe_amount_cents,
        currency: currency,
        voice_tier: voice_tier,
        method: :stripe
      ).data

      MppPayment.create!(
        amount_cents: tempo_amount_cents,
        currency: currency,
        challenge_id: tempo_challenge[:id],
        deposit_address: deposit_address,
        stripe_payment_intent_id: payment_intent_id,
        status: :pending
      )

      MppPayment.create!(
        amount_cents: stripe_amount_cents,
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

    attr_reader :tempo_amount_cents, :stripe_amount_cents, :currency, :voice_tier
  end
end
