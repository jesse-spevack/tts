class AddSourceTextToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :episodes, :source_text, :text
  end
end
