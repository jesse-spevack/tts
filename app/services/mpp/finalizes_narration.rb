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
      # Wrap the winner's flip + narration insert in one transaction so
      # losers never observe a half-committed state (status=completed
      # with no linked Narration yet). Without the wrapper, a loser whose
      # update_all returns 0 can race the winner's narration insert and
      # get a transient "payment finalized but narration pending" failure,
      # which would surface as a 500 on a client's idempotent retry.
      ActiveRecord::Base.transaction do
        update_attrs = {
          status: "completed",
          tx_hash: tx_hash,
          updated_at: Time.current
        }
        # stripe-scheme rows: tx_hash is the SPT PI; tempo rows have it set in ProvisionsChallenge.
        update_attrs[:stripe_payment_intent_id] = tx_hash if mpp_payment.deposit_address.blank?

        rows_updated = MppPayment
          .where(id: mpp_payment.id, status: "pending")
          .update_all(update_attrs)

        if rows_updated == 1
          mpp_payment.reload
          creation = CreatesNarration.call(mpp_payment: mpp_payment, params: params)
          raise ActiveRecord::Rollback if creation.failure?

          return Result.success(narration: creation.data, outcome: :winner)
        end
      end

      # Either we lost the race OR we were the winner but CreatesNarration
      # failed (rolled back). In both cases the authoritative state is
      # in the DB now — look up the committed Narration.
      mpp_payment.reload
      existing = Narration.find_by(mpp_payment_id: mpp_payment.id)
      if existing
        Result.success(narration: existing, outcome: :loser)
      else
        # True failure: winner rolled back AND no other winner committed.
        # Controller treats this as a transient conflict.
        Result.failure("Payment already finalized but narration pending")
      end
    end

    private

    attr_reader :mpp_payment, :tx_hash, :params
  end
end
