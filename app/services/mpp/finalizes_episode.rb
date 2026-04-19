# frozen_string_literal: true

module Mpp
  # Finalizes an authenticated MPP payment → Episode creation with a
  # race-safe guard (agent-team-kzq). Mirror of Mpp::FinalizesNarration
  # for the bearer-authenticated Episode path.
  #
  # Same race, same fix: atomic pending→completed status transition on
  # MppPayment, with a row-count check to distinguish winner from loser.
  # The winner proceeds to create the Episode; the loser returns a
  # clean error (outcome: :loser, episode: nil) which the controller
  # maps to 409 Conflict.
  #
  # Loser semantics differ from the Narration path: episodes do not
  # currently populate episodes.mpp_payment_id during the MPP flow,
  # so we cannot look up the winner's Episode for idempotent retry.
  # A clean 409 is the acceptable alternative per the bead's AC
  # ("idempotent OR clean error — but NOT two resources").
  class FinalizesEpisode
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, mpp_payment:, tx_hash:, params:, voice_override:)
      @user = user
      @mpp_payment = mpp_payment
      @tx_hash = tx_hash
      @params = params
      @voice_override = voice_override
    end

    def call
      # Wrap the winner's flip + episode insert in one transaction so
      # a creation failure rolls back the payment flip too — otherwise
      # the payment stays status=completed with no linked Episode and
      # no refund callback fires (Narration#after_update won't because
      # no Narration exists), stranding the money.
      ActiveRecord::Base.transaction do
        rows_updated = MppPayment
          .where(id: mpp_payment.id, status: "pending")
          .update_all(
            status: "completed",
            tx_hash: tx_hash,
            user_id: user.id,
            updated_at: Time.current
          )

        if rows_updated == 1
          mpp_payment.reload
          creation = CreatesEpisode.call(
            user: user,
            params: params,
            voice_override: voice_override
          )
          raise ActiveRecord::Rollback if creation.failure?

          return Result.success(episode: creation.data, outcome: :winner)
        end
      end

      # Lost the race (or winner rolled back). Episodes don't expose an
      # idempotent-retry lookup — return clean loser outcome. Controller
      # renders 409.
      mpp_payment.reload
      Result.success(episode: nil, outcome: :loser)
    end

    private

    attr_reader :user, :mpp_payment, :tx_hash, :params, :voice_override
  end
end
