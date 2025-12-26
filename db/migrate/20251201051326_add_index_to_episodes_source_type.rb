class AddIndexToEpisodesSourceType < ActiveRecord::Migration[8.1]
  def change
    add_index :episodes, :source_type
  end
end
