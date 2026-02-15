class AddProcessingColumnsToEpisodes < ActiveRecord::Migration[8.1]
  def up
    add_column :episodes, :processing_started_at, :datetime
    add_column :episodes, :processing_completed_at, :datetime
    add_column :episodes, :source_text_length, :integer

    # Backfill completed episodes with best-approximation timestamps
    # processing_started_at = created_at (includes queue wait, best we have)
    # processing_completed_at = updated_at (completion is the last update)
    execute <<~SQL
      UPDATE episodes
      SET processing_started_at = created_at,
          processing_completed_at = updated_at
      WHERE status = 'complete'
    SQL

    # Backfill source_text_length for all episodes that have source_text
    execute <<~SQL
      UPDATE episodes
      SET source_text_length = LENGTH(source_text)
      WHERE source_text IS NOT NULL
    SQL
  end

  def down
    remove_column :episodes, :processing_started_at
    remove_column :episodes, :processing_completed_at
    remove_column :episodes, :source_text_length
  end
end
