class AddCanceledAtToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :canceled_at, :datetime
  end
end
