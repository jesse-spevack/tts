class CreateEpisodeUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :episode_usages do |t|
      t.references :user, null: false, foreign_key: true
      t.date :period_start, null: false
      t.integer :episode_count, default: 0, null: false
      t.timestamps

      t.index [ :user_id, :period_start ], unique: true
    end
  end
end
