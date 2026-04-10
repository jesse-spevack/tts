# frozen_string_literal: true

class CreateMppPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :mpp_payments do |t|
      t.string :public_id, null: false
      t.string :stripe_payment_intent_id
      t.string :deposit_address
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :status, null: false, default: "pending"
      t.integer :narration_id
      t.integer :user_id
      t.string :challenge_id
      t.string :tx_hash

      t.timestamps
    end

    add_index :mpp_payments, :public_id, unique: true
    add_index :mpp_payments, :stripe_payment_intent_id
    add_index :mpp_payments, :tx_hash, unique: true
    add_index :mpp_payments, :user_id
  end
end
