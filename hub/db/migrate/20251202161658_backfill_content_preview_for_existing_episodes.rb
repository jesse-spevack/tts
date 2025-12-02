class BackfillContentPreviewForExistingEpisodes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE episodes SET content_preview = 'No preview available' WHERE content_preview IS NULL
    SQL
  end

  def down
    execute <<~SQL
      UPDATE episodes SET content_preview = NULL WHERE content_preview = 'No preview available'
    SQL
  end
end
