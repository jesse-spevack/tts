class DropPublicIdFromMppPaymentsAndNarrations < ActiveRecord::Migration[8.1]
  def change
    remove_index :mpp_payments, :public_id
    remove_column :mpp_payments, :public_id, :string, null: false

    remove_index :narrations, :public_id
    remove_column :narrations, :public_id, :string, null: false
  end
end
