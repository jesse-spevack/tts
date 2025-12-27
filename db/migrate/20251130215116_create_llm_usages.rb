class CreateLlmUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_usages do |t|
      t.references :episode, null: false, foreign_key: true
      t.string :model_id, null: false
      t.string :provider, null: false
      t.integer :input_tokens, null: false
      t.integer :output_tokens, null: false
      t.decimal :cost_cents, precision: 10, scale: 4

      t.timestamps
    end
  end
end
