class CreatePodcasts < ActiveRecord::Migration[8.1]
  def change
    create_table :podcasts do |t|
      t.string :podcast_id, null: false
      t.string :title
      t.text :description

      t.timestamps
    end

    add_index :podcasts, :podcast_id, unique: true
  end
end
