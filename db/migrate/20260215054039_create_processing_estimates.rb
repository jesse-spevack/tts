class CreateProcessingEstimates < ActiveRecord::Migration[8.1]
  def change
    create_table :processing_estimates do |t|
      t.integer :base_seconds, null: false
      t.integer :microseconds_per_character, null: false
      t.integer :episode_count, null: false
      t.datetime :created_at, null: false
    end
  end
end
