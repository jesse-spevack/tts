class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_customer_id, null: false
      t.string :stripe_subscription_id, null: false
      t.string :stripe_price_id, null: false
      t.integer :status, null: false, default: 0
      t.datetime :current_period_end, null: false
      t.timestamps
    end

    add_index :subscriptions, :stripe_customer_id, unique: true
    add_index :subscriptions, :stripe_subscription_id, unique: true
  end
end
