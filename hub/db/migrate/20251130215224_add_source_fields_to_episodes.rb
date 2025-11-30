class AddSourceFieldsToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :episodes, :source_url, :string
    add_column :episodes, :source_type, :integer, default: 0, null: false
  end
end
