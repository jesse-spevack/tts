class AddDeletedAtToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :episodes, :deleted_at, :datetime
    add_index :episodes, :deleted_at
  end
end
