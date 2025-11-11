class CreateEpisodes < ActiveRecord::Migration[8.1]
  def change
    create_table :episodes do |t|
      t.references :podcast, null: false, foreign_key: true
      t.string :title, null: false
      t.string :author, null: false
      t.text :description, null: false
      t.string :status, null: false, default: 'pending'
      t.string :gcs_episode_id
      t.text :error_message
      t.integer :audio_size_bytes
      t.integer :duration_seconds

      t.timestamps
    end

    add_index :episodes, :status
    add_index :episodes, :gcs_episode_id
  end
end
