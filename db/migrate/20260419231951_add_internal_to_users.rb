class AddInternalToUsers < ActiveRecord::Migration[8.1]
  # Adds an `internal` flag to users so admin metrics queries can exclude
  # Jesse's own traffic from user-facing counts. No default_scope — callers
  # filter explicitly via `where(internal: false)` when they want to exclude
  # internal users.
  def up
    add_column :users, :internal, :boolean, default: false, null: false

    # Backfill the known internal accounts: user_id 1 (jspevack@gmail.com)
    # and user_id 11 (jessespevack@stripe.com). These IDs are stable in prod
    # and dev; in environments where they don't exist (e.g. fresh test DBs)
    # this is a no-op.
    execute(<<~SQL.squish)
      UPDATE users
      SET internal = 1
      WHERE id IN (1, 11)
    SQL
  end

  def down
    remove_column :users, :internal
  end
end
