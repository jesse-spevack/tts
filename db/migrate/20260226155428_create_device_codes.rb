class CreateDeviceCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :device_codes do |t|
      t.string :device_code, null: false
      t.string :user_code, null: false
      t.references :user, null: true, foreign_key: true
      t.string :token
      t.datetime :expires_at, null: false
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :device_codes, :device_code, unique: true
    add_index :device_codes, :user_code, unique: true
  end
end
