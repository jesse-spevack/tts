# frozen_string_literal: true

class CreateProcessedWebhookEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_webhook_emails do |t|
      t.string :email_id, null: false
      t.string :source, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :processed_webhook_emails, [:source, :email_id], unique: true
  end
end
