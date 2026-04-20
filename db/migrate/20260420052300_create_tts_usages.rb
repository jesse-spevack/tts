class CreateTtsUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :tts_usages do |t|
      t.references :usable, polymorphic: true, null: false, index: { unique: true }
      t.string :provider, null: false
      t.string :voice_id, null: false
      t.string :voice_tier, null: false
      t.integer :character_count, null: false
      t.integer :cost_cents, null: false
      t.string :source, null: false, default: "actual"

      t.timestamps
    end
  end
end
