class CreateDeactivations < ActiveRecord::Migration[8.1]
  def change
    create_table :deactivations do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :deactivated_at, null: false
      t.string :reason

      t.timestamps
    end
  end
end
