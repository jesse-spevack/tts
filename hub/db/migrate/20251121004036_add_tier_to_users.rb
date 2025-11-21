class AddTierToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tier, :integer, default: 0
  end
end
