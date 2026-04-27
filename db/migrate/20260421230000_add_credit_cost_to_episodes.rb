# frozen_string_literal: true

# Adds Episode#credit_cost — the credits charged for this episode — promoting
# what was previously computed on the fly from CreditTransaction into a real
# attribute on the model (agent-team-0rwa, absorbed by agent-team-gafe).
#
# Column is nullable to preserve the "deferred cost" state: a URL episode
# that has been submitted but not yet fetched has credit_cost: nil. Once
# ProcessesUrlEpisode computes the real cost post-extract, it writes it.
# A value of 0 means "no debit applies" (free tier / complimentary / unlimited).
#
# Named `credit_cost` (not `cost_cents`) to avoid unit confusion with
# TtsUsage.cost_cents, which stores USD cents (Google provider cost).
class AddCreditCostToEpisodes < ActiveRecord::Migration[8.0]
  def up
    add_column :episodes, :credit_cost, :integer

    # Backfill from existing CreditTransaction usage rows (one-to-one with
    # episodes that were actually charged). Mirrors the source
    # episode_cost_label reads today.
    execute <<~SQL.squish
      UPDATE episodes
      SET credit_cost = ABS(credit_transactions.amount)
      FROM credit_transactions
      WHERE credit_transactions.episode_id = episodes.id
        AND credit_transactions.transaction_type = 'usage'
    SQL

    # Remaining NULLs are episodes that never had a usage transaction:
    # free-tier, complimentary, unlimited, or very early data. All had zero
    # credits debited — collapse to 0 so forward code can rely on
    # "NULL means genuinely deferred (URL extract pending)" without
    # historical noise.
    execute <<~SQL.squish
      UPDATE episodes
      SET credit_cost = 0
      WHERE credit_cost IS NULL
    SQL
  end

  def down
    remove_column :episodes, :credit_cost
  end
end
