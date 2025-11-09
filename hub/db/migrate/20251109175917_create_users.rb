class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address
      t.string :auth_token
      t.datetime :auth_token_expires_at

      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, :auth_token
  end
end
