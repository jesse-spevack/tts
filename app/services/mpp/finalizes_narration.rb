# frozen_string_literal: true

module Mpp
  # Finalizes an anonymous MPP payment → Narration creation with a
  # race-safe guard (agent-team-kzq).
  #
  # Two simultaneous POSTs with the same valid Payment credential both
  # pass Mpp::VerifiesCredential (the MppPayment.exists?(tx_hash:)
  # replay check races the subsequent update!), both find the same
  # pending MppPayment by challenge_id, and without this guard both
  # would create a Narration. One payment → two narrations.
  #
  # The guard is an atomic status transition:
  #
  #     MppPayment.where(id:, status: :pending).update_all(
  #       status: :completed, tx_hash:, updated_at: now
  #     )
  #
  # The SQL WHERE ... UPDATE is a single statement and the DB
  # serializes concurrent writers. Exactly one caller sees row-count
  # == 1 (the winner); all others see row-count == 0 (the losers).
  # The winner proceeds to create the Narration. Losers look up the
  # winner's Narration via narrations.mpp_payment_id (which is
  # uniquely indexed as a belt-and-suspenders backstop — see
  # db/migrate/..._add_unique_index_to_narrations_mpp_payment_id.rb)
  # and return it, giving idempotent retry semantics.
  #
  # Returns Result.success(narration:, outcome: :winner|:loser).
  # Controller is responsible for headers (Payment-Receipt) and HTTP
  # status — both winner and loser render 201.
  class FinalizesNarration
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(mpp_payment:, tx_hash:, params:)
      @mpp_payment = mpp_payment
      @tx_hash = tx_hash
      @params = params
    end

    def call
      rows_updated = MppPayment
        .where(id: mpp_payment.id, status: "pending")
        .update_all(
          status: "completed",
          tx_hash: tx_hash,
          updated_at: Time.current
        )

      if rows_updated == 1
        # Winner: we flipped the pending row. Refresh our local copy
        # so callers see the new state, then create the Narration.
        mpp_payment.reload
        creation = CreatesNarration.call(mpp_payment: mpp_payment, params: params)
        return creation if creation.failure?

        Result.success(narration: creation.data, outcome: :winner)
      else
        # Loser: another caller already won the race. Look up the
        # winner's Narration and return it for idempotent retry.
        # narrations.mpp_payment_id is uniquely indexed so find_by
        # is guaranteed to return at most one row.
        mpp_payment.reload
        existing = Narration.find_by(mpp_payment_id: mpp_payment.id)
        if existing
          Result.success(narration: existing, outcome: :loser)
        else
          # Degenerate case: status flipped but Narration not yet
          # persisted by the winner thread. Controller treats this
          # as a transient conflict (retry-friendly).
          Result.failure("Payment already finalized but narration pending")
        end
      end
    end

    private

    attr_reader :mpp_payment, :tx_hash, :params
  end
end
