class AddIndexToSubscriptionsCurrentPeriodEnd < ActiveRecord::Migration[8.1]
  def change
    add_index :subscriptions, :current_period_end
  end
end
