class DropFreeEpisodeClaims < ActiveRecord::Migration[8.1]
  def up
    drop_table :free_episode_claims
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
