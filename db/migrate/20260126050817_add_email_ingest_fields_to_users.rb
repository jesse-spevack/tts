class AddEmailIngestFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_ingest_token, :string
    add_index :users, :email_ingest_token, unique: true
    add_column :users, :email_episodes_enabled, :boolean, default: false, null: false
  end
end
