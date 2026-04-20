class AddCanceledAtToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :canceled_at, :datetime
  end
end
