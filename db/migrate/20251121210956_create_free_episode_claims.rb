class CreateFreeEpisodeClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :free_episode_claims do |t|
      t.references :user, null: false, foreign_key: true
      t.references :episode, null: false, foreign_key: true
      t.datetime :claimed_at, null: false
      t.datetime :released_at

      t.timestamps
    end
  end
end
