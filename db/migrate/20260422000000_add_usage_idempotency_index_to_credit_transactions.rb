# frozen_string_literal: true

class AddUsageIdempotencyIndexToCreditTransactions < ActiveRecord::Migration[8.1]
  def change
    add_index :credit_transactions, [ :user_id, :episode_id ],
      unique: true,
      where: "transaction_type = 'usage'",
      name: "idx_credit_transactions_usage_unique"
  end
end
