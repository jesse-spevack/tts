class AddAccountTypeToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :account_type, :integer, default: 0, null: false

    # Migrate existing unlimited users
    execute <<-SQL
      UPDATE users SET account_type = 2 WHERE tier = 2
    SQL

    remove_column :users, :tier
  end

  def down
    add_column :users, :tier, :integer, default: 0

    # Restore unlimited users
    execute <<-SQL
      UPDATE users SET tier = 2 WHERE account_type = 2
    SQL

    remove_column :users, :account_type
  end
end
