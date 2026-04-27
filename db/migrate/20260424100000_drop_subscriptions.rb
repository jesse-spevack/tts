class DropSubscriptions < ActiveRecord::Migration[8.1]
  def up
    drop_table :subscriptions
  end

  def down
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_subscription_id, null: false
      t.string :stripe_price_id, null: false
      t.integer :status, null: false, default: 0
      t.datetime :current_period_end, null: false
      t.datetime :cancel_at
      t.datetime :canceled_at
      t.timestamps
    end

    add_index :subscriptions, :stripe_subscription_id, unique: true
    add_index :subscriptions, :current_period_end
  end
end
