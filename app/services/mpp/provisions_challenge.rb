# frozen_string_literal: true

module Mpp
  # Provisions a 402 Payment Required challenge: allocates a Stripe-backed
  # crypto deposit address (used by the Tempo on-chain path), HMAC-signs
  # parallel tempo + stripe challenges against a single price/expiry, and
  # persists one pending MppPayment row per challenge_id.
  #
  # The two-row design is a deliberate trade-off (see bd note on
  # agent-team-k71e.1): each method's challenge_id is unique because the
  # method is part of the HMAC pre-image, and Mpp::VerifiesCredential
  # looks up its MppPayment row via challenge_id (verifies_credential.rb:52).
  # Persisting one row per challenge keeps that lookup unchanged across
  # methods. The client picks ONE method at retry time; the other row
  # stays pending and gets swept by CleanupStaleMppPaymentsJob after
  # CHALLENGE_TTL_SECONDS.
  #
  # Returns Result.success(Provisioned) on success. Controller owns
  # the response rendering (WWW-Authenticate header + 402 JSON body);
  # this service owns the business logic.
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
      # Step 1: provision the Stripe PaymentIntent + Tempo deposit address
      # FIRST so the on-chain recipient is known before we sign the tempo
      # challenge. The stripe-method challenge does not need this — but
      # we issue both challenges from the same provisioning call to keep
      # them aligned on amount/expiry/voice_tier.
      deposit_result = Mpp::CreatesDepositAddress.call(
        amount_cents: amount_cents,
        currency: currency
      )
      return deposit_result unless deposit_result.success?

      deposit_address = deposit_result.data[:deposit_address]
      payment_intent_id = deposit_result.data[:payment_intent_id]

      # Step 2: sign each challenge. Tempo binds the deposit_address into
      # its HMAC; stripe binds AppConfig::Mpp::STRIPE_NETWORK_ID instead
      # (SPTs are not chain-bound, so there's no per-charge address).
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

      # Step 3: persist one pending MppPayment row per challenge_id.
      # The tempo row carries deposit_address + the deposit-PI; the
      # stripe row carries neither (Mpp::VerifiesSptCredential, k71e.5,
      # will populate stripe_payment_intent_id with the SPT-redemption PI
      # at verify time). VerifiesCredential resolves its row via
      # challenge_id, so each method's verifier sees its own row.
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
