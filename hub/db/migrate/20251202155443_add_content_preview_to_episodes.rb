class AddContentPreviewToEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :episodes, :content_preview, :text, default: "No preview available"
  end
end
