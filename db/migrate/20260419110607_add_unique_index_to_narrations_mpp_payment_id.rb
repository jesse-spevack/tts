# frozen_string_literal: true

# Belt-and-suspenders backstop for the double-spend race (agent-team-kzq).
#
# The primary guard is the atomic MppPayment status transition in the
# controller (pending → completed via update_all with row-count check),
# which prevents two concurrent requests from both claiming the same
# pending payment. This unique index is the DB-level safety net: if
# anything ever bypasses the controller guard, the second Narration
# insert will raise ActiveRecord::RecordNotUnique instead of silently
# creating a duplicate.
#
# Scope: narrations only. Episodes do not currently populate
# episodes.mpp_payment_id during the MPP create flow, so a unique
# index there would be inert. The atomic status transition in
# Api::V1::Mpp::EpisodesController covers that path.
class AddUniqueIndexToNarrationsMppPaymentId < ActiveRecord::Migration[8.1]
  def change
    remove_index :narrations, :mpp_payment_id
    add_index :narrations, :mpp_payment_id, unique: true
  end
end
