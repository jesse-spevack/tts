# frozen_string_literal: true

class CreateCreditBalances < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_balances do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :balance, null: false, default: 0
      t.timestamps
    end
  end
end
