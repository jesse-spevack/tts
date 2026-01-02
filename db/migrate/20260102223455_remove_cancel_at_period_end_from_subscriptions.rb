class RemoveCancelAtPeriodEndFromSubscriptions < ActiveRecord::Migration[8.1]
  def change
    remove_column :subscriptions, :cancel_at_period_end, :boolean, default: false, null: false
  end
end
