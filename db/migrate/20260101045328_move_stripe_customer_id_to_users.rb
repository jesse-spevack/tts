class MoveStripeCustomerIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :stripe_customer_id, :string
    add_index :users, :stripe_customer_id, unique: true

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE users
          SET stripe_customer_id = subscriptions.stripe_customer_id
          FROM subscriptions
          WHERE subscriptions.user_id = users.id
        SQL
      end
    end

    remove_column :subscriptions, :stripe_customer_id, :string
  end
end
