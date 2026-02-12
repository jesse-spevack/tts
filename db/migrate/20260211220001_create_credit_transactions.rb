# frozen_string_literal: true

class CreateCreditTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.integer :balance_after, null: false
      t.string :transaction_type, null: false
      t.string :stripe_session_id
      t.references :episode, foreign_key: true
      t.timestamps
    end

    add_index :credit_transactions, :transaction_type
    add_index :credit_transactions, :stripe_session_id, unique: true
  end
end
