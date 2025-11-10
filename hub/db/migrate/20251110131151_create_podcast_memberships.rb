class CreatePodcastMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :podcast_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :podcast, null: false, foreign_key: true

      t.timestamps
    end

    add_index :podcast_memberships, [ :user_id, :podcast_id ], unique: true
  end
end
