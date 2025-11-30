class AddUserToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_reference :episodes, :user, foreign_key: true

    # Backfill existing episodes with their podcast's first user
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE episodes
          SET user_id = (
            SELECT podcast_memberships.user_id
            FROM podcast_memberships
            WHERE podcast_memberships.podcast_id = episodes.podcast_id
            LIMIT 1
          )
          WHERE user_id IS NULL
        SQL
      end
    end
  end
end
